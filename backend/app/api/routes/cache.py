"""Cache observability endpoint — a live gauge for the 1,000-credit budget.

GET /api/cache/stats returns hit/miss counters, hit rate, and estimated credits saved.
Handy during the demo to prove the caching layer is doing its job.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import cache_stats
from app.config import settings
from app.db.database import get_db

router = APIRouter()


@router.get("/cache/stats")
async def get_cache_stats(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    """Return in-memory cache metrics plus the L2 (PostgreSQL) row count.

    The in-memory metrics always work. The L2 count is best-effort: if the database
    is unreachable (e.g. local dev without Postgres running), it comes back as null
    rather than failing the whole endpoint.
    """
    stats = cache_stats()

    l2_entries: int | None
    try:
        l2_entries = (await db.execute(text("SELECT COUNT(*) FROM sectors_cache"))).scalar_one()
    except Exception:
        l2_entries = None

    return {
        **stats,
        "l2_entries": l2_entries,
        "mock_mode": settings.use_mock_data,
    }
