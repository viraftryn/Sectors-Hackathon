"""Read/write stocks and stock_scores (schema: supabase/migrations/*_invelio_schema.sql)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import _coerce_dt


def _pct(value: float | None) -> float | None:
    return None if value is None else round(value * 100, 2)


async def save_scores(db: AsyncSession, results: list[dict[str, Any]]) -> datetime:
    # Timezone-aware: asyncpg reads naive datetimes as machine-local time for TIMESTAMPTZ.
    now = datetime.now(UTC)
    for r in results:
        q = r["quote"]
        await db.execute(
            text(
                "INSERT INTO stocks (ticker, symbol, name, sector, sub_sector, price, change_pct, "
                "market_cap, pe_ttm, pb_mrq, roe_ttm, der_mrq, yield_ttm, week52_high, "
                "week52_low, updated_at) "
                "VALUES (:ticker, :symbol, :name, :sector, :sub_sector, :price, :change_pct, "
                ":market_cap, :pe, :pb, :roe, :der, :yield, :high, :low, :now) "
                "ON CONFLICT (ticker) DO UPDATE SET symbol = :symbol, name = :name, "
                "sector = :sector, sub_sector = :sub_sector, price = :price, "
                "change_pct = :change_pct, market_cap = :market_cap, pe_ttm = :pe, "
                "pb_mrq = :pb, roe_ttm = :roe, der_mrq = :der, yield_ttm = :yield, "
                "week52_high = :high, week52_low = :low, updated_at = :now"
            ),
            {
                "ticker": r["ticker"],
                "symbol": f"{r['ticker']}.JK",
                "name": r["name"],
                "sector": r["sector"],
                "sub_sector": r["sub_sector"],
                "price": q["last_close_price"],
                "change_pct": _pct(q.get("daily_close_change")),
                "market_cap": q.get("market_cap"),
                "pe": q.get("pe_ttm"),
                "pb": q.get("pb_mrq"),
                "roe": _pct(q.get("roe_ttm")),
                "der": q.get("der_mrq"),
                "yield": _pct(q.get("yield_ttm")),
                "high": q.get("52_w_high_price"),
                "low": q.get("52_w_low_price"),
                "now": now,
            },
        )
        await db.execute(
            text(
                "INSERT INTO stock_scores (ticker, fundamental_score, macro_score, sector_score, "
                "risk_score, sentiment_score, overall_score, recommendation, reasoning, scored_at) "
                "VALUES (:ticker, :fundamental, :macro, :sector, :risk, :sentiment, :overall, "
                ":recommendation, :reasoning, :now)"
            ),
            {
                "ticker": r["ticker"],
                **r["components"],
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
            "FROM stock_scores s "
            "JOIN (SELECT ticker, MAX(scored_at) AS latest FROM stock_scores GROUP BY ticker) l "
            "ON s.ticker = l.ticker AND s.scored_at = l.latest "
            "JOIN stocks st ON st.ticker = s.ticker "
            "ORDER BY s.overall_score DESC"
        )
    )
    return [
        {
            **row._mapping,
            "scored_at": _coerce_dt(row.scored_at),
            **{
                k: float(row._mapping[k])
                for k in (
                    "fundamental_score",
                    "macro_score",
                    "sector_score",
                    "risk_score",
                    "sentiment_score",
                    "overall_score",
                )
            },
        }
        for row in rows
    ]


async def last_scored_at(db: AsyncSession) -> datetime | None:
    value = (await db.execute(text("SELECT MAX(scored_at) FROM stock_scores"))).scalar()
    return _coerce_dt(value) if value is not None else None
