"""Read/write stock_ai_insights table for daily per-ticker AI analysis."""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

ORDER_MAP = {
    "technical": 1,
    "fundamentals": 2,
    "sentiment": 3,
    "outlook": 4,
}


async def save_stock_insights(
    db: AsyncSession, ticker: str, insights: list[dict[str, Any]], gen_date: date | None = None
) -> None:
    now = datetime.now(UTC)
    target_date = gen_date or date.today()
    clean_ticker = ticker.upper()

    for item in insights:
        await db.execute(
            text(
                "INSERT INTO stock_ai_insights "
                "(ticker, analysis_type, label, content, generated_date, created_at) "
                "VALUES (:ticker, :type, :label, :content, :date, :now) "
                "ON CONFLICT (ticker, analysis_type, generated_date) DO UPDATE SET "
                "content = :content, label = :label, created_at = :now"
            ),
            {
                "ticker": clean_ticker,
                "type": item["analysis_type"],
                "label": item["label"],
                "content": item["content"],
                "date": target_date,
                "now": now,
            },
        )
    await db.commit()


async def latest_stock_insights(db: AsyncSession, ticker: str) -> list[dict[str, Any]]:
    clean_ticker = ticker.upper()
    rows = await db.execute(
        text(
            "SELECT ticker, analysis_type, label, content, generated_date, created_at "
            "FROM stock_ai_insights "
            "WHERE ticker = :ticker "
            "  AND generated_date = ("
            "      SELECT MAX(generated_date) FROM stock_ai_insights WHERE ticker = :ticker"
            "  ) "
            "ORDER BY id"
        ),
        {"ticker": clean_ticker},
    )
    results = [dict(r._mapping) for r in rows]
    # Sort according to canonical ordering (Technical, Fundamentals, Sentiment, Outlook)
    results.sort(key=lambda x: ORDER_MAP.get(x.get("analysis_type", ""), 99))
    return results


async def stock_insights_generated_today(db: AsyncSession, ticker: str) -> bool:
    clean_ticker = ticker.upper()
    result = await db.execute(
        text(
            "SELECT COUNT(*) FROM stock_ai_insights "
            "WHERE ticker = :ticker AND generated_date = CURRENT_DATE"
        ),
        {"ticker": clean_ticker},
    )
    return (result.scalar() or 0) >= 4


async def get_tracked_tickers_from_db(db: AsyncSession) -> list[str]:
    result = await db.execute(text("SELECT ticker FROM stocks ORDER BY ticker ASC"))
    return [r[0] for r in result.fetchall()]
