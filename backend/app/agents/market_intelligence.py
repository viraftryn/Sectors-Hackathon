"""Market Intelligence Agent: gather_data -> generate_insights (LangGraph).

Reads cached market data from the database (stocks, scores, daily prices,
market overview) and asks Gemini to produce three daily insight paragraphs:
Technical Analysis, News Sentiment, Macro & Currency.

The date is embedded in the prompt so the LLM varies its wording each day,
even when the underlying data hasn't changed.
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any, TypedDict, cast

from langgraph.graph import END, START, StateGraph
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.clients.llm import LLMError, generate_json

logger = logging.getLogger(__name__)

ANALYSIS_TYPES = [
    {"key": "technical", "label": "Technical Analysis"},
    {"key": "sentiment", "label": "News Sentiment"},
    {"key": "macro", "label": "Macro & Currency"},
]


class InsightState(TypedDict, total=False):
    db_data: dict[str, Any]
    insights: list[dict[str, Any]]


async def _fetch_stocks(db: AsyncSession) -> list[dict[str, Any]]:
    rows = await db.execute(
        text(
            "SELECT ticker, name, sector, sub_sector, price, change_pct, "
            "pe_ttm, pb_mrq, roe_ttm, der_mrq, yield_ttm, "
            "week52_high, week52_low "
            "FROM stocks ORDER BY ticker"
        )
    )
    return [dict(r._mapping) for r in rows]


async def _fetch_scores(db: AsyncSession) -> list[dict[str, Any]]:
    rows = await db.execute(
        text(
            "SELECT s.ticker, st.name, s.fundamental_score, s.macro_score, "
            "s.sector_score, s.risk_score, s.sentiment_score, "
            "s.overall_score, s.recommendation, s.reasoning "
            "FROM stock_scores s "
            "JOIN (SELECT ticker, MAX(scored_at) AS latest "
            "      FROM stock_scores GROUP BY ticker) l "
            "ON s.ticker = l.ticker AND s.scored_at = l.latest "
            "JOIN stocks st ON st.ticker = s.ticker "
            "ORDER BY s.overall_score DESC"
        )
    )
    return [dict(r._mapping) for r in rows]


async def _fetch_daily_prices(db: AsyncSession) -> dict[str, list[dict[str, Any]]]:
    rows = await db.execute(
        text(
            "SELECT ticker, date, open, high, low, close, volume "
            "FROM stock_daily_prices "
            "WHERE date >= CURRENT_DATE - INTERVAL '30 days' "
            "ORDER BY ticker, date"
        )
    )
    prices: dict[str, list[dict[str, Any]]] = {}
    for r in rows:
        m = dict(r._mapping)
        m["date"] = str(m["date"])
        prices.setdefault(m["ticker"], []).append(m)
    return prices


async def _fetch_market_overview(db: AsyncSession) -> dict[str, Any] | None:
    row = await db.execute(
        text(
            "SELECT ihsg_value, ihsg_change_pct, foreign_inflow, "
            "top_gainers, top_losers "
            "FROM market_overview_cache WHERE id = 'latest'"
        )
    )
    r = row.first()
    return dict(r._mapping) if r else None


SYSTEM_PROMPT = """\
You are a senior Indonesian stock market analyst writing daily market intelligence \
briefings for retail investors. Your analysis covers stocks listed on the Indonesia \
Stock Exchange (IDX).

RULES:
- Write in English.
- Use markdown bold (**text**) to highlight key tickers, numbers, and terms.
- Each insight should be 2-4 sentences, concise and actionable.
- Vary your wording and angle every day — even if the data is the same, find a \
different framing, metaphor, or emphasis so repeat readers don't see identical text.
- Reference specific tickers, numbers, and percentages from the data provided.
- Do NOT give explicit buy/sell advice. Frame as observations and analysis.
- For Technical Analysis: focus on price action, momentum, volume, support/resistance, \
RSI-like signals inferred from the price data.
- For News Sentiment: focus on which tickers have positive or negative scoring \
momentum, recommendation changes, and market perception.
- For Macro & Currency: focus on IHSG index performance, foreign fund flows, and \
broader market conditions.
"""


def _build_prompt(db_data: dict[str, Any], today: str) -> str:
    lines = [
        f"Today's date: {today}. Generate fresh market intelligence for today.",
        "",
        "Return JSON with exactly this structure:",
        '[{"analysis_type": "technical", "content": "..."},',
        ' {"analysis_type": "sentiment", "content": "..."},',
        ' {"analysis_type": "macro", "content": "..."}]',
        "",
        "=== STOCK FUNDAMENTALS ===",
    ]

    for s in db_data.get("stocks", []):
        lines.append(
            f"{s['ticker']} ({s['name']}): price={s['price']}, "
            f"change={s.get('change_pct', 'N/A')}%, "
            f"PE={s.get('pe_ttm', 'N/A')}, PB={s.get('pb_mrq', 'N/A')}, "
            f"ROE={s.get('roe_ttm', 'N/A')}%, "
            f"52wH={s.get('week52_high', 'N/A')}, 52wL={s.get('week52_low', 'N/A')}"
        )

    scores = db_data.get("scores", [])
    if scores:
        lines.append("")
        lines.append("=== AI SCORES & RECOMMENDATIONS ===")
        for sc in scores:
            lines.append(
                f"{sc['ticker']} ({sc['name']}): overall={sc['overall_score']}, "
                f"rec={sc['recommendation']}, "
                f"fundamental={sc['fundamental_score']}, macro={sc['macro_score']}, "
                f"sector={sc['sector_score']}, risk={sc['risk_score']}, "
                f"sentiment={sc['sentiment_score']}"
            )

    daily = db_data.get("daily_prices", {})
    if daily:
        lines.append("")
        lines.append("=== RECENT PRICE DATA (last 30 days) ===")
        for ticker, prices in daily.items():
            if len(prices) >= 2:
                latest = prices[-1]
                prev = prices[-2]
                vol_avg = sum(p.get("volume", 0) or 0 for p in prices[-5:]) / min(5, len(prices))
                min_p = min(p["close"] for p in prices)
                max_p = max(p["close"] for p in prices)
                lines.append(
                    f"{ticker}: latest close={latest['close']}, "
                    f"prev close={prev['close']}, "
                    f"30d range={min_p}-{max_p}, "
                    f"5d avg vol={vol_avg:.0f}"
                )

    overview = db_data.get("market_overview")
    if overview:
        lines.append("")
        lines.append("=== MARKET OVERVIEW ===")
        lines.append(
            f"IHSG: value={overview.get('ihsg_value', 'N/A')}, "
            f"change={overview.get('ihsg_change_pct', 'N/A')}%"
        )
        if overview.get("foreign_inflow") is not None:
            direction = "inflow" if overview["foreign_inflow"] >= 0 else "outflow"
            lines.append(f"Foreign net {direction}: Rp {abs(overview['foreign_inflow']):,.0f}")

    return "\n".join(lines)


FALLBACK_INSIGHTS = [
    {
        "analysis_type": "technical",
        "label": "Technical Analysis",
        "content": (
            "**Banking sector** shows mixed signals across IDX-listed names. "
            "Price action across major tickers suggests consolidation near key levels. "
            "Monitor volume trends for confirmation of the next directional move."
        ),
    },
    {
        "analysis_type": "sentiment",
        "label": "News Sentiment",
        "content": (
            "Market sentiment is cautiously optimistic across tracked IDX stocks. "
            "AI scoring shows most names holding steady recommendations. "
            "Watch for shifts in institutional positioning."
        ),
    },
    {
        "analysis_type": "macro",
        "label": "Macro & Currency",
        "content": (
            "**IHSG** is tracking within its recent range. "
            "Foreign fund flows remain a key driver of near-term direction. "
            "Broader macro conditions continue to influence investor appetite."
        ),
    },
]


def build_intelligence_graph(db: AsyncSession) -> Any:
    async def gather_data(state: InsightState) -> InsightState:
        stocks = await _fetch_stocks(db)
        scores = await _fetch_scores(db)
        daily_prices = await _fetch_daily_prices(db)
        overview = await _fetch_market_overview(db)
        return {
            "db_data": {
                "stocks": stocks,
                "scores": scores,
                "daily_prices": daily_prices,
                "market_overview": overview,
            }
        }

    async def generate_insights(state: InsightState) -> InsightState:
        today = date.today().isoformat()
        prompt = _build_prompt(state["db_data"], today)
        label_map = {t["key"]: t["label"] for t in ANALYSIS_TYPES}

        try:
            raw = await generate_json(prompt, SYSTEM_PROMPT, temperature=0.8)
            insights = []
            for item in raw:
                atype = item["analysis_type"]
                insights.append(
                    {
                        "analysis_type": atype,
                        "label": label_map.get(atype, atype.title()),
                        "content": item["content"],
                    }
                )
            if len(insights) == 3:
                return {"insights": insights}
            logger.warning("LLM returned %d insights instead of 3, using fallback", len(insights))
        except (LLMError, TypeError, KeyError, IndexError) as exc:
            logger.warning("Market intelligence LLM failed, using fallback: %s", exc)

        return {"insights": FALLBACK_INSIGHTS}

    graph = StateGraph(InsightState)
    graph.add_node("gather_data", gather_data)
    graph.add_node("generate_insights", generate_insights)
    graph.add_edge(START, "gather_data")
    graph.add_edge("gather_data", "generate_insights")
    graph.add_edge("generate_insights", END)
    return graph.compile()


async def run_market_intelligence(db: AsyncSession) -> list[dict[str, Any]]:
    final = await build_intelligence_graph(db).ainvoke({})
    return cast(list[dict[str, Any]], final["insights"])
