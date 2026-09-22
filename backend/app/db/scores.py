"""Read/write the scores and stocks tables (schema in app/db/schema.sql)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import _coerce_dt, _utcnow


async def save_scores(db: AsyncSession, results: list[dict[str, Any]]) -> datetime:
    now = _utcnow()
    for r in results:
        await db.execute(
            text(
                "INSERT INTO stocks (ticker, name, sector, subsector, updated_at) "
                "VALUES (:ticker, :name, :sector, :subsector, :now) "
                "ON CONFLICT (ticker) DO UPDATE SET name = :name, sector = :sector, "
                "subsector = :subsector, updated_at = :now"
            ),
            {
                "ticker": r["ticker"],
                "name": r["name"],
                "sector": r["sector"],
                "subsector": r["sub_sector"],
                "now": now,
            },
        )
        c = r["components"]
        await db.execute(
            text(
                "INSERT INTO scores (ticker, fundamental_score, macro_score, sector_score, "
                "risk_score, sentiment_score, overall_score, recommendation, reasoning, scored_at) "
                "VALUES (:ticker, :fundamental, :macro, :sector, :risk, :sentiment, :overall, "
                ":recommendation, :reasoning, :now)"
            ),
            {
                "ticker": r["ticker"],
                **c,
                "overall": r["overall_score"],
                "recommendation": r["recommendation"],
                "reasoning": r["reasoning"],
                "now": now,
            },
        )
    await db.commit()
    return now


async def latest_scores(db: AsyncSession) -> list[dict[str, Any]]:
    rows = await db.execute(
        text(
            "SELECT s.ticker, st.name, s.fundamental_score, s.macro_score, s.sector_score, "
            "s.risk_score, s.sentiment_score, s.overall_score, s.recommendation, s.reasoning, "
            "s.scored_at "
            "FROM scores s "
            "JOIN (SELECT ticker, MAX(scored_at) AS latest FROM scores GROUP BY ticker) l "
            "ON s.ticker = l.ticker AND s.scored_at = l.latest "
            "JOIN stocks st ON st.ticker = s.ticker "
            "ORDER BY s.overall_score DESC"
        )
    )
    return [{**row._mapping, "scored_at": _coerce_dt(row.scored_at)} for row in rows]


async def last_scored_at(db: AsyncSession) -> datetime | None:
    value = (await db.execute(text("SELECT MAX(scored_at) FROM scores"))).scalar()
    return _coerce_dt(value) if value is not None else None
