"""Scoring Agent: fetch_market_data -> compute_scores -> llm_reasoning (LangGraph).

Five components, each 0-100 (higher is better, so a high risk score means low risk):
fundamental 30%, macro 15%, sector 20%, risk 15%, sentiment 20%.
"""

from __future__ import annotations

import logging
import math
import re
import statistics
from collections.abc import Awaitable, Callable
from typing import Any, TypedDict, cast

from langgraph.graph import END, START, StateGraph

from app.clients.cached_sectors import CachedSectorsClient
from app.clients.llm import LLMError, generate_json
from app.clients.sectors import bare_symbol

logger = logging.getLogger(__name__)

WEIGHTS = {"fundamental": 0.30, "macro": 0.15, "sector": 0.20, "risk": 0.15, "sentiment": 0.20}
BUY_AT = 65.0
SELL_AT = 40.0
NEUTRAL = 50.0
RECOMMENDATIONS = ("BUY", "HOLD", "SELL")

ReasonFn = Callable[[str, str], Awaitable[Any]]


class ScoringState(TypedDict, total=False):
    market: dict[str, Any]
    stocks: dict[str, dict[str, Any]]
    results: list[dict[str, Any]]


def scale(value: float, zero_at: float, full_at: float) -> float:
    """Linear map with zero_at -> 0 and full_at -> 100, clamped. zero_at may exceed full_at."""
    ratio = (value - zero_at) / (full_at - zero_at)
    return round(max(0.0, min(1.0, ratio)) * 100, 1)


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def period_return(closes: list[float], days: int) -> float | None:
    if len(closes) <= days or closes[-1 - days] == 0:
        return None
    return closes[-1] / closes[-1 - days] - 1


def fundamental_score(q: dict[str, Any], sector_median_pe: float | None) -> float:
    parts = []
    pe = q.get("pe_ttm")
    if pe is not None:
        if pe <= 0:
            parts.append(0.0)
        elif sector_median_pe:
            parts.append(scale(pe / sector_median_pe, 1.6, 0.6))
        else:
            parts.append(scale(pe, 25, 8))
    if q.get("pb_mrq") is not None:
        parts.append(scale(q["pb_mrq"], 5, 1))
    if q.get("roe_ttm") is not None:
        parts.append(scale(min(q["roe_ttm"], 0.4), 0, 0.2))
    if q.get("der_mrq") is not None:
        parts.append(scale(q["der_mrq"], 2, 0.5))
    if q.get("yield_ttm") is not None:
        parts.append(scale(q["yield_ttm"], 0, 0.08))
    return round(statistics.mean(parts), 1) if parts else NEUTRAL


def macro_score(ihsg_closes: list[float], flow: list[dict[str, Any]]) -> float:
    parts = []
    trend = period_return(ihsg_closes, min(20, len(ihsg_closes) - 1))
    if trend is not None:
        parts.append(scale(trend, -0.05, 0.05))
    recent = flow[-20:]
    turnover = sum(d["foreign_buy_idr"] + d["foreign_sell_idr"] for d in recent)
    if turnover:
        net = sum(d["net_foreign_inflow"] for d in recent)
        parts.append(scale(net / turnover, -0.1, 0.1))
    return round(statistics.mean(parts), 1) if parts else NEUTRAL


def sector_score(sector_1w: float | None, ihsg_1w: float | None) -> float:
    if sector_1w is None or ihsg_1w is None:
        return NEUTRAL
    return scale(sector_1w - ihsg_1w, -0.05, 0.05)


def risk_score(closes: list[float]) -> float:
    if len(closes) < 10:
        return NEUTRAL
    returns = [math.log(b / a) for a, b in zip(closes, closes[1:], strict=False) if a > 0]
    volatility = statistics.stdev(returns) * math.sqrt(252)
    peak, drawdown = closes[0], 0.0
    for close in closes:
        peak = max(peak, close)
        drawdown = min(drawdown, close / peak - 1)
    return round((scale(volatility, 0.6, 0.15) + scale(drawdown, -0.3, 0)) / 2, 1)


def sentiment_score(news: list[dict[str, Any]], filings: list[dict[str, Any]]) -> float:
    parts: list[tuple[float, float]] = []
    bullish = sum("Bullish" in a.get("tags", []) for a in news)
    bearish = sum("Bearish" in a.get("tags", []) for a in news)
    if bullish + bearish:
        parts.append((scale((bullish - bearish) / (bullish + bearish), -1, 1), 0.7))
    bought = sum(f["transaction_value"] for f in filings if f.get("transaction_type") == "buy")
    sold = sum(f["transaction_value"] for f in filings if f.get("transaction_type") == "sell")
    if bought + sold:
        parts.append((scale((bought - sold) / (bought + sold), -1, 1), 0.3))
    if not parts:
        return NEUTRAL
    return round(sum(s * w for s, w in parts) / sum(w for _, w in parts), 1)


def recommend(overall: float) -> str:
    if overall >= BUY_AT:
        return "BUY"
    if overall <= SELL_AT:
        return "SELL"
    return "HOLD"


def fallback_reasoning(result: dict[str, Any]) -> str:
    components = sorted(result["components"].items(), key=lambda kv: kv[1])
    weakest, strongest = components[0], components[-1]
    return (
        f"{result['ticker']} scores {result['overall_score']:.0f}/100. "
        f"Strongest factor: {strongest[0]} ({strongest[1]:.0f}); "
        f"weakest: {weakest[0]} ({weakest[1]:.0f})."
    )


SYSTEM_PROMPT = (
    "You are an equity analyst for the Indonesia Stock Exchange. You receive quantitative "
    "scores (0-100, higher is better; a high risk score means low risk) computed from Sectors "
    "API data. For each stock return a recommendation (BUY, HOLD or SELL) and 2-3 sentences of "
    "reasoning in English that cite the numbers given. Use only the data provided."
)


def build_prompt(results: list[dict[str, Any]]) -> str:
    lines = [
        'Return JSON: [{"ticker": str, "recommendation": "BUY"|"HOLD"|"SELL", '
        '"reasoning": str}] with one entry per stock.',
        "",
    ]
    for r in results:
        lines.append(
            f"{r['ticker']} ({r['name']}, {r['sub_sector']}): overall {r['overall_score']}, "
            f"suggested {r['recommendation']}, components {r['components']}, metrics {r['metrics']}"
        )
    return "\n".join(lines)


def build_scoring_graph(sectors: CachedSectorsClient, reason: ReasonFn | None = None) -> Any:
    reason_fn = reason or generate_json

    async def fetch_market_data(state: ScoringState) -> ScoringState:
        # Sequential on purpose: CachedSectorsClient shares one DB session.
        companies = cast(dict[str, Any], await sectors.list_companies())["results"]
        ihsg = cast(list[dict[str, Any]], await sectors.get_ihsg())
        market_flow = cast(dict[str, Any], await sectors.get_foreign_flow("IHSG"))

        sector_reports: dict[str, dict[str, Any]] = {}
        stocks: dict[str, dict[str, Any]] = {}
        for row in companies:
            ticker = bare_symbol(row["symbol"])
            slug = slugify(row["query_values"]["sub_sector"])
            if slug not in sector_reports:
                sector_reports[slug] = cast(dict[str, Any], await sectors.get_sector_report(slug))
            news = cast(dict[str, Any], await sectors.get_news(ticker))
            filings = cast(dict[str, Any], await sectors.get_news_filings(ticker))
            stocks[ticker] = {
                "name": row["company_name"],
                "quote": row["query_values"],
                "sector_report": sector_reports[slug],
                "daily": await sectors.get_daily_prices(ticker),
                "news": news["results"],
                "filings": filings["results"],
            }
        return {
            "market": {"ihsg": [p["price"] for p in ihsg], "flow": market_flow["data"]},
            "stocks": stocks,
        }

    async def compute_scores(state: ScoringState) -> ScoringState:
        ihsg = state["market"]["ihsg"]
        ihsg_1w = period_return(ihsg, 5)
        macro = macro_score(ihsg, state["market"]["flow"])
        results = []
        for ticker, data in state["stocks"].items():
            q = data["quote"]
            report = data["sector_report"]
            median_pe = report.get("statistics", {}).get("filtered_median_pe")
            sector_1w = (
                report.get("market_cap", {})
                .get("mcap_summary", {})
                .get("mcap_change", {})
                .get("1w")
            )
            closes = [d["close"] for d in data["daily"]]
            components = {
                "fundamental": fundamental_score(q, median_pe),
                "macro": macro,
                "sector": sector_score(sector_1w, ihsg_1w),
                "risk": risk_score(closes),
                "sentiment": sentiment_score(data["news"], data["filings"]),
            }
            overall = round(sum(components[k] * w for k, w in WEIGHTS.items()), 1)
            results.append(
                {
                    "ticker": ticker,
                    "name": data["name"],
                    "sector": q["sector"],
                    "sub_sector": q["sub_sector"],
                    "components": components,
                    "overall_score": overall,
                    "recommendation": recommend(overall),
                    "metrics": {
                        "pe": q.get("pe_ttm"),
                        "pb": q.get("pb_mrq"),
                        "roe": q.get("roe_ttm"),
                        "der": q.get("der_mrq"),
                        "dividend_yield": q.get("yield_ttm"),
                        "sector_median_pe": median_pe,
                        "return_1m": period_return(closes, 20),
                        "news_count": len(data["news"]),
                    },
                }
            )
        results.sort(key=lambda r: r["overall_score"], reverse=True)
        return {"results": results}

    async def llm_reasoning(state: ScoringState) -> ScoringState:
        results = [dict(r) for r in state["results"]]
        try:
            answer = await reason_fn(build_prompt(results), SYSTEM_PROMPT)
            by_ticker = {bare_symbol(a["ticker"]): a for a in answer if isinstance(a, dict)}
        except (LLMError, TypeError, KeyError) as exc:
            logger.warning("Scoring LLM unavailable, using rule-based reasoning: %s", exc)
            by_ticker = {}
        for r in results:
            llm = by_ticker.get(r["ticker"], {})
            if llm.get("recommendation") in RECOMMENDATIONS and llm.get("reasoning"):
                r["recommendation"] = llm["recommendation"]
                r["reasoning"] = str(llm["reasoning"])
            else:
                r["reasoning"] = fallback_reasoning(r)
        return {"results": results}

    graph = StateGraph(ScoringState)
    graph.add_node("fetch_market_data", fetch_market_data)
    graph.add_node("compute_scores", compute_scores)
    graph.add_node("llm_reasoning", llm_reasoning)
    graph.add_edge(START, "fetch_market_data")
    graph.add_edge("fetch_market_data", "compute_scores")
    graph.add_edge("compute_scores", "llm_reasoning")
    graph.add_edge("llm_reasoning", END)
    return graph.compile()


async def run_scoring(
    sectors: CachedSectorsClient, reason: ReasonFn | None = None
) -> list[dict[str, Any]]:
    final = await build_scoring_graph(sectors, reason).ainvoke({})
    return cast(list[dict[str, Any]], final["results"])
