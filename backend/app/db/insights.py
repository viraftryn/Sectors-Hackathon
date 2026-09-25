"""Read/write market_intelligence table for daily AI-generated insights."""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def save_insights(db: AsyncSession, insights: list[dict[str, Any]]) -> None:
    now = datetime.now(UTC)
    today = date.today()
    for item in insights:
        await db.execute(
            text(
                "INSERT INTO market_intelligence "
                "(analysis_type, label, content, generated_date, created_at) "
                "VALUES (:type, :label, :content, :date, :now) "
                "ON CONFLICT (analysis_type, generated_date) DO UPDATE SET "
                "content = :content, label = :label, created_at = :now"
            ),
            {
                "type": item["analysis_type"],
                "label": item["label"],
                "content": item["content"],
                "date": today,
                "now": now,
            },
        )
    await db.commit()


async def latest_insights(db: AsyncSession) -> list[dict[str, Any]]:
    rows = await db.execute(
        text(
            "SELECT analysis_type, label, content, generated_date, created_at "
            "FROM market_intelligence "
            "WHERE generated_date = (SELECT MAX(generated_date) FROM market_intelligence) "
            "ORDER BY id"
        )
    )
    return [dict(row._mapping) for row in rows]


async def insights_generated_today(db: AsyncSession) -> bool:
    result = await db.execute(
        text(
            "SELECT COUNT(*) FROM market_intelligence "
            "WHERE generated_date = CURRENT_DATE"
        )
    )
    return (result.scalar() or 0) >= 3
