"""Chatbot Agent — LangGraph workflow with Sectors MCP / REST tool-calling.

Three-node graph: classify_question -> retrieve_context -> generate_response.
The LLM autonomously picks which Sectors tools to query based on the user's
question — this is the agentic tool-use behavior.

Two data modes controlled by ``settings.use_mcp``:
  - **MCP** (demo): connects to the hosted Sectors MCP server — live data,
    burns API credits per question.
  - **REST** (development default): uses CachedSectorsClient with two-layer
    cache (L1 memory + L2 PostgreSQL) — saves credits.
"""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, TypedDict, cast

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import (
    AIMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langchain_core.tools import tool
from langgraph.graph import END, StateGraph
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import cache_get, cache_set
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import bare_symbol
from app.config import settings

logger = logging.getLogger(__name__)

MAX_TOOL_RESULT_CHARS = 4000
MAX_TOOL_ROUNDS = 3

MCP_TOOL_WHITELIST = {
    "fetch-company-report",
    "fetch-daily-transaction",
    "fetch-companies-by-subsector",
    "fetch-most-traded-stocks",
    "fetch-companies-top-changes",
    "fetch-index-daily",
    "fetch-subsector-report",
    "fetch-news",
    "fetch-filings",
    "get-subsectors",
}

TICKER_PARAM_NAMES = {"symbol", "symbols", "ticker"}

MCP_DEFAULT_ARGS: dict[str, dict[str, Any]] = {
    "fetch-company-report": {"sections": "overview,valuation"},
    "fetch-companies-top-changes": {"periods": "1d", "n_stock": 5},
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------


class ChatState(TypedDict):
    user_message: str
    chat_history: list[dict[str, str]]
    question_type: str
    entities: list[str]
    context: list[dict[str, Any]]
    response: str


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

CLASSIFY_PROMPT = """\
You are a financial question classifier for Indonesian stock market (IDX) analysis.

Classify the user's message into one of these types:
- single_stock: About a specific stock (e.g. "How is BBCA performing?")
- comparison: Comparing two or more stocks (e.g. "Compare BBCA vs BMRI")
- sector: About a sector/industry (e.g. "How is the banking sector?")
- market: About the overall market or IHSG index
- general: General finance question, greeting, or unclear

Extract any stock tickers mentioned (uppercase IDX tickers like BBCA, TLKM).

Respond ONLY with valid JSON:
{"question_type": "...", "entities": ["TICKER1", "TICKER2"]}"""

RETRIEVAL_PROMPT = """\
You are a data retrieval agent for Indonesian stock market analysis.
Use the available tools to fetch the Sectors data needed to answer the user's question.

Rules:
- For single stock questions, fetch the company report and optionally news.
- For comparisons, fetch company reports for each ticker.
- For sector questions, fetch the sector/subsector report.
- For market questions, fetch market index data and top movers.
- Call multiple tools when comparing stocks.
- IDX tickers do NOT include the .JK suffix (e.g. use BBCA, not BBCA.JK).
- Do NOT fabricate data — only return what the tools provide.

Question type: {question_type}
Detected tickers: {entities}"""

RESPONSE_PROMPT = """\
You are Invelio, an AI financial assistant for the Indonesian stock market (IDX).

Your answers MUST be grounded in the retrieved Sectors data below.
Never fabricate financial numbers. If the data is insufficient, say so.

Guidelines:
- Be concise and informative (2-4 paragraphs)
- Use actual numbers from the data (prices, ratios, percentages)
- Format currency as Indonesian Rupiah (e.g. Rp 8,450)
- Present data objectively — do not give explicit buy/sell financial advice
- Reference the data source (e.g. "Based on the latest Sectors data...")
- For comparisons, use a structured format

## Retrieved Sectors Data
{context}"""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _truncate(text: str, max_chars: int = MAX_TOOL_RESULT_CHARS) -> str:
    if len(text) <= max_chars:
        return text
    return text[:max_chars] + "\n... [truncated]"


def _extract_text(content: Any) -> str:
    """Normalize LLM content to a plain string (Gemini returns a list of blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            block.get("text", "") if isinstance(block, dict) else str(block) for block in content
        )
    return str(content)


def _get_llm(temperature: float = 0.0, streaming: bool = False) -> BaseChatModel:
    if settings.chatbot_provider == "gemini":
        from langchain_google_genai import ChatGoogleGenerativeAI

        return ChatGoogleGenerativeAI(
            model=settings.chatbot_model,
            temperature=temperature,
            google_api_key=settings.gemini_api_key,
            streaming=streaming,
            max_retries=1,
        )
    from langchain_openai import ChatOpenAI

    return ChatOpenAI(
        model=settings.chatbot_model,
        temperature=temperature,
        api_key=SecretStr(settings.openai_api_key) if settings.openai_api_key else None,
        streaming=streaming,
    )


# ---------------------------------------------------------------------------
# REST tools — wraps CachedSectorsClient (development mode)
# ---------------------------------------------------------------------------


def _validate_ticker(ticker: str) -> str | None:
    """Return normalized ticker if tracked, else None."""
    t = ticker.upper().removesuffix(".JK")
    return t if t in settings.tracked_tickers else None


def _build_rest_tools(client: CachedSectorsClient) -> list[Any]:
    @tool
    async def get_company_report(ticker: str) -> str:
        """Get a company's financial report: overview, valuation
        (PE, PBV, ROE, DER), market cap, dividend yield.

        Tracked: BBCA BBRI BMRI BBNI TLKM ASII UNVR ICBP AMRT ANTM."""
        t = _validate_ticker(ticker)
        if t is None:
            return f"Ticker {ticker!r} is not tracked."
        data = await client.get_company_report(t)
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_daily_prices(ticker: str) -> str:
        """Get 90-day daily OHLCV price history for a stock.

        Tracked: BBCA BBRI BMRI BBNI TLKM ASII UNVR ICBP AMRT ANTM."""
        t = _validate_ticker(ticker)
        if t is None:
            return f"Ticker {ticker!r} is not tracked."
        data = await client.get_daily_prices(t)
        if isinstance(data, list) and len(data) > 10:
            summary = {
                "total_days": len(data),
                "latest_10": data[-10:],
                "oldest": data[0] if data else None,
            }
            return _truncate(json.dumps(summary, default=str))
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_stock_list() -> str:
        """Get all tracked IDX stocks with sector, sub-sector, and latest price."""
        data = await client.list_companies()
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_most_traded() -> str:
        """Get today's most actively traded stocks by volume."""
        data = await client.get_most_traded()
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_top_movers() -> str:
        """Get today's top gainers and top losers in the IDX market."""
        data = await client.get_top_companies()
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_market_index() -> str:
        """Get the IHSG (Jakarta Composite Index) data and recent trend."""
        data = await client.get_ihsg()
        if isinstance(data, list) and len(data) > 10:
            summary = {"total_days": len(data), "latest_10": data[-10:]}
            return _truncate(json.dumps(summary, default=str))
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_sector_report(sub_sector: str) -> str:
        """Get performance report for an IDX sub-sector.

        Valid sub-sectors: banks, telecommunication, basic-materials, food-beverage,
        food-staples-retailing, multi-sector-holdings, nondurable-household-products."""
        data = await client.get_sector_report(sub_sector)
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_news(ticker: str = "") -> str:
        """Get latest news articles. Pass a ticker for stock-specific
        news, or empty string for all market news."""
        if ticker:
            t = _validate_ticker(ticker)
            if t is None:
                return f"Ticker {ticker!r} is not tracked."
            data = await client.get_news(t)
        else:
            data = await client.get_news(None)
        return _truncate(json.dumps(data, default=str))

    @tool
    async def get_insider_transactions(ticker: str = "") -> str:
        """Get insider transactions (buy/sell) for a stock.
        Pass a ticker or empty for all."""
        if ticker:
            t = _validate_ticker(ticker)
            if t is None:
                return f"Ticker {ticker!r} is not tracked."
            data = await client.get_news_filings(t)
        else:
            data = await client.get_news_filings(None)
        return _truncate(json.dumps(data, default=str))

    return [
        get_company_report,
        get_daily_prices,
        get_stock_list,
        get_most_traded,
        get_top_movers,
        get_market_index,
        get_sector_report,
        get_news,
        get_insider_transactions,
    ]


# ---------------------------------------------------------------------------
# MCP tools — connects to hosted Sectors MCP server (demo mode)
# ---------------------------------------------------------------------------


def _guard_mcp_args(tool_name: str, args: dict[str, Any]) -> dict[str, Any] | str:
    """Validate ticker and inject cost-saving defaults for MCP tool calls.

    Returns the cleaned args dict, or an error string if the ticker is rejected.
    """
    guarded = dict(args)

    for param in TICKER_PARAM_NAMES:
        if param not in guarded:
            continue
        raw = guarded[param]
        if isinstance(raw, str):
            tickers = [t.strip() for t in raw.split(",")]
        elif isinstance(raw, list):
            tickers = raw
        else:
            continue
        cleaned = [t.upper().removesuffix(".JK") for t in tickers if t.strip()]
        rejected = [t for t in cleaned if t not in settings.tracked_tickers]
        if rejected:
            allowed = ", ".join(settings.tracked_tickers)
            return f"Ticker {', '.join(rejected)} not tracked. Use: {allowed}"
        guarded[param] = ",".join(f"{t}.JK" for t in cleaned) if isinstance(raw, str) else cleaned

    defaults = MCP_DEFAULT_ARGS.get(tool_name, {})
    for key, value in defaults.items():
        if key not in guarded:
            guarded[key] = value

    return guarded


def _wrap_mcp_tool(original: Any) -> Any:
    """Wrap an MCP tool with ticker validation and default-arg injection."""
    real_ainvoke = original.ainvoke

    async def guarded_ainvoke(input: Any, config: Any = None, **kwargs: Any) -> Any:  # noqa: A002
        args = input if isinstance(input, dict) else {"input": input}
        result = _guard_mcp_args(original.name, args)
        if isinstance(result, str):
            return result
        return await real_ainvoke(result, config, **kwargs)

    original.ainvoke = guarded_ainvoke

    if hasattr(original, "invoke"):
        real_invoke = original.invoke

        def guarded_invoke(input: Any, config: Any = None, **kwargs: Any) -> Any:  # noqa: A002
            args = input if isinstance(input, dict) else {"input": input}
            result = _guard_mcp_args(original.name, args)
            if isinstance(result, str):
                return result
            return real_invoke(result, config, **kwargs)

        original.invoke = guarded_invoke

    return original


def _mcp_cache_key(tool_name: str, args: dict[str, Any]) -> tuple[str, int] | None:
    """Map an MCP tool call to (cache_key, ttl). Returns None if not cacheable."""
    def _ticker(args: dict[str, Any]) -> str:
        for p in TICKER_PARAM_NAMES:
            raw = args.get(p, "")
            if raw:
                t = raw.split(",")[0].strip() if isinstance(raw, str) else raw[0]
                return bare_symbol(t)
        return ""

    mapping: dict[str, tuple[str, int]] = {
        "fetch-company-report": (
            f"company_report:{_ticker(args)}",
            settings.cache_ttl_fundamentals,
        ),
        "fetch-daily-transaction": (
            f"daily_prices:{_ticker(args)}",
            settings.cache_ttl_prices,
        ),
        "fetch-companies-by-subsector": (
            "companies_list",
            settings.cache_ttl_prices,
        ),
        "fetch-most-traded-stocks": (
            "most_traded",
            settings.cache_ttl_prices,
        ),
        "fetch-companies-top-changes": (
            "top_companies",
            settings.cache_ttl_prices,
        ),
        "fetch-index-daily": (
            "ihsg",
            settings.cache_ttl_market_index,
        ),
        "fetch-subsector-report": (
            f"sector_report:{args.get('sub_sector', args.get('subsector', ''))}",
            settings.cache_ttl_sector_reports,
        ),
        "fetch-news": (
            f"news:{_ticker(args)}" if _ticker(args) else "news:all",
            settings.cache_ttl_news,
        ),
        "fetch-filings": (
            f"news_filings:{_ticker(args)}" if _ticker(args) else "news_filings:all",
            settings.cache_ttl_sector_reports,
        ),
        "get-subsectors": (
            "subsectors",
            settings.cache_ttl_sector_reports,
        ),
    }
    return mapping.get(tool_name)


def _wrap_mcp_tool_cached(original: Any, db: AsyncSession | None) -> Any:
    """Wrap an MCP tool with L1/L2 cache — same keys and TTLs as CachedSectorsClient."""
    guarded = _wrap_mcp_tool(original)
    real_ainvoke = guarded.ainvoke

    async def cached_ainvoke(input: Any, config: Any = None, **kwargs: Any) -> Any:  # noqa: A002
        args = input if isinstance(input, dict) else {"input": input}
        cache_info = _mcp_cache_key(original.name, args)
        if cache_info is not None:
            cache_key, ttl = cache_info
            mcp_key = f"mcp:{cache_key}"
            hit = await cache_get(mcp_key, db)
            if hit is not None:
                logger.debug("MCP cache hit: %s", mcp_key)
                return hit.get("result", hit)
            result = await real_ainvoke(input, config, **kwargs)
            await cache_set(mcp_key, {"result": result}, ttl, db)
            return result
        return await real_ainvoke(input, config, **kwargs)

    guarded.ainvoke = cached_ainvoke
    return guarded


@asynccontextmanager
async def _mcp_tools(db: AsyncSession | None = None) -> Any:
    """Connect to Sectors MCP server and yield cache-wrapped LangChain tools."""
    from langchain_mcp_adapters.tools import load_mcp_tools
    from mcp import ClientSession
    from mcp.client.streamable_http import streamablehttp_client

    url = settings.sectors_mcp_url
    headers = {"Authorization": f"Bearer {settings.sectors_api_key}"}
    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            all_tools = await load_mcp_tools(session)
            tools = [
                _wrap_mcp_tool_cached(t, db)
                for t in all_tools
                if t.name in MCP_TOOL_WHITELIST
            ]
            logger.info("Loaded %d/%d MCP tools from Sectors (cache-enabled)", len(tools), len(all_tools))
            yield tools


# ---------------------------------------------------------------------------
# Unified tool loader
# ---------------------------------------------------------------------------


@asynccontextmanager
async def _get_tools(db: AsyncSession | None = None) -> Any:
    """Yield tools from MCP (demo) or REST+cache (development)."""
    if settings.use_mcp:
        logger.info("Chatbot mode: MCP (live Sectors data, cache-enabled)")
        async with _mcp_tools(db) as tools:
            yield tools
    else:
        logger.info("Chatbot mode: REST + cache")
        client = CachedSectorsClient(db)
        yield _build_rest_tools(client)


# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------


class ChatbotAgent:
    """LangGraph chatbot with Sectors tool-calling (MCP or REST).

    Nodes:
      1. classify_question  — categorize the question + extract tickers
      2. retrieve_context   — LLM picks which Sectors tools to call (agentic)
      3. generate_response  — produce a grounded answer from retrieved data
    """

    def __init__(self, db: AsyncSession | None = None) -> None:
        self._db = db
        self._tools: list[Any] = []
        self._tool_map: dict[str, Any] = {}

    # -- Node implementations -----------------------------------------------

    async def _classify_question(self, state: ChatState) -> dict[str, Any]:
        llm = _get_llm(temperature=0.0)
        result = await llm.ainvoke(
            [
                SystemMessage(content=CLASSIFY_PROMPT),
                HumanMessage(content=state["user_message"]),
            ]
        )
        try:
            parsed = json.loads(_extract_text(result.content))
            return {
                "question_type": parsed.get("question_type", "general"),
                "entities": parsed.get("entities", []),
            }
        except (json.JSONDecodeError, AttributeError, TypeError):
            return {"question_type": "general", "entities": []}

    async def _retrieve_context(self, state: ChatState) -> dict[str, Any]:
        llm_with_tools = _get_llm(temperature=0.0).bind_tools(self._tools)
        system = RETRIEVAL_PROMPT.format(
            question_type=state["question_type"],
            entities=state["entities"],
        )
        messages: list[Any] = [
            SystemMessage(content=system),
            HumanMessage(content=state["user_message"]),
        ]

        context_parts: list[dict[str, Any]] = []
        for _ in range(MAX_TOOL_ROUNDS):
            result = await llm_with_tools.ainvoke(messages)
            messages.append(result)

            if not result.tool_calls:
                break

            for tc in result.tool_calls:
                fn = self._tool_map.get(tc["name"])
                if fn is None:
                    tool_output = f"Unknown tool: {tc['name']}"
                else:
                    try:
                        tool_output = await fn.ainvoke(tc["args"])
                        tool_output = _truncate(str(tool_output))
                    except Exception as exc:
                        logger.warning("Tool %s failed: %s", tc["name"], exc)
                        tool_output = f"Error fetching data: {exc}"

                context_parts.append({"tool": tc["name"], "args": tc["args"], "data": tool_output})
                messages.append(ToolMessage(content=str(tool_output), tool_call_id=tc["id"]))

        return {"context": context_parts}

    def _format_context(self, context: list[dict[str, Any]]) -> str:
        parts = []
        for item in context:
            args_str = (
                ", ".join(f"{k}={v!r}" for k, v in item["args"].items()) if item["args"] else ""
            )
            parts.append(f"### {item['tool']}({args_str})\n{item['data']}")
        return "\n\n".join(parts) if parts else "(no data retrieved)"

    def _build_response_messages(self, state: ChatState) -> list[Any]:
        context_text = self._format_context(state.get("context", []))
        system = RESPONSE_PROMPT.format(context=context_text)

        history_msgs: list[Any] = []
        for msg in (state.get("chat_history") or [])[-6:]:
            if msg["role"] == "user":
                history_msgs.append(HumanMessage(content=msg["content"]))
            else:
                history_msgs.append(AIMessage(content=msg["content"]))

        return [
            SystemMessage(content=system),
            *history_msgs,
            HumanMessage(content=state["user_message"]),
        ]

    async def _generate_response(self, state: ChatState) -> dict[str, Any]:
        llm = _get_llm(temperature=0.3)
        messages = self._build_response_messages(state)
        result = await llm.ainvoke(messages)
        return {"response": _extract_text(result.content)}

    # -- Graph ---------------------------------------------------------------

    def _build_graph(self) -> Any:
        graph = StateGraph(ChatState)
        graph.add_node("classify_question", self._classify_question)
        graph.add_node("retrieve_context", self._retrieve_context)
        graph.add_node("generate_response", self._generate_response)
        graph.set_entry_point("classify_question")
        graph.add_edge("classify_question", "retrieve_context")
        graph.add_edge("retrieve_context", "generate_response")
        graph.add_edge("generate_response", END)
        return graph.compile()

    # -- Public API ----------------------------------------------------------

    async def run(self, message: str, history: list[dict[str, str]] | None = None) -> str:
        """Execute the full pipeline and return the complete response."""
        async with _get_tools(self._db) as tools:
            self._tools = tools
            self._tool_map = {t.name: t for t in tools}
            graph = self._build_graph()
            initial: ChatState = {
                "user_message": message,
                "chat_history": history or [],
                "question_type": "",
                "entities": [],
                "context": [],
                "response": "",
            }
            result = await graph.ainvoke(initial)
            return cast(str, result["response"])

    async def stream(
        self, message: str, history: list[dict[str, str]] | None = None
    ) -> AsyncIterator[str]:
        """Run classify + retrieve, then stream the final response tokens."""
        async with _get_tools(self._db) as tools:
            self._tools = tools
            self._tool_map = {t.name: t for t in tools}

            state: ChatState = {
                "user_message": message,
                "chat_history": history or [],
                "question_type": "",
                "entities": [],
                "context": [],
                "response": "",
            }

            classified = await self._classify_question(state)
            state["question_type"] = classified["question_type"]
            state["entities"] = classified["entities"]

            retrieved = await self._retrieve_context(state)
            state["context"] = retrieved["context"]

            messages = self._build_response_messages(state)
            llm = _get_llm(temperature=0.3, streaming=True)
            async for chunk in llm.astream(messages):
                text = _extract_text(chunk.content) if chunk.content else ""
                if text:
                    yield text
