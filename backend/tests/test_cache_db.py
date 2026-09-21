"""Tests for the L2 (PostgreSQL) path and the full two-layer flow, via in-memory SQLite."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import (
    _memory,
    _utcnow,
    cache_get,
    cache_invalidate,
    cache_set,
    cache_stats,
    memory_cache_clear,
)


async def _age_row(db: AsyncSession, key: str, seconds: float) -> None:
    """Backdate a row's cached_at so its TTL math treats it as older."""
    await db.execute(
        text("UPDATE sectors_cache SET cached_at = :t WHERE cache_key = :k"),
        {"t": _utcnow() - timedelta(seconds=seconds), "k": key},
    )
    await db.commit()


async def _row_count(db: AsyncSession, key: str) -> int:
    return (
        await db.execute(
            text("SELECT COUNT(*) FROM sectors_cache WHERE cache_key = :k"), {"k": key}
        )
    ).scalar_one()


async def test_set_then_get_serves_from_l1(db: AsyncSession) -> None:
    await cache_set("daily_prices:BBCA", {"close": 9800}, ttl=300, db=db)
    result = await cache_get("daily_prices:BBCA", db)
    assert result == {"close": 9800}
    # Served from L1, so no L2 hit recorded.
    assert cache_stats()["l1_hits"] == 1
    assert cache_stats()["l2_hits"] == 0


async def test_get_falls_through_to_l2_and_repopulates_l1(db: AsyncSession) -> None:
    await cache_set("company_report:BBCA", {"pe": 22.3}, ttl=86400, db=db)
    memory_cache_clear()  # simulate a server restart / eviction

    assert _memory.get("company_report:BBCA") is None
    result = await cache_get("company_report:BBCA", db)

    assert result == {"pe": 22.3}
    assert cache_stats()["l2_hits"] == 1
    # L1 was warmed back up from L2.
    assert _memory.get("company_report:BBCA") == {"pe": 22.3}


async def test_get_missing_key_returns_none(db: AsyncSession) -> None:
    assert await cache_get("does_not_exist", db) is None
    assert cache_stats()["misses"] == 1


async def test_expired_l2_entry_is_evicted(db: AsyncSession) -> None:
    await cache_set("idx_total", {"close": 7250}, ttl=5, db=db)
    memory_cache_clear()
    await _age_row(db, "idx_total", seconds=10)  # older than its 5s TTL

    assert await cache_get("idx_total", db) is None
    assert await _row_count(db, "idx_total") == 0  # stale row deleted
    assert cache_stats()["misses"] == 1


async def test_l2_promotion_uses_remaining_ttl_not_full_ttl(db: AsyncSession) -> None:
    await cache_set("sector_report", {"x": 1}, ttl=100, db=db)
    memory_cache_clear()
    await _age_row(db, "sector_report", seconds=90)  # 90 of 100s already elapsed

    await cache_get("sector_report", db)  # promotes to L1

    _data, _cached_at, l1_ttl = _memory._store["sector_report"]
    # Remaining TTL is ~10s, definitely not the full 100s (the old bug).
    assert 1 <= l1_ttl <= 15


async def test_upsert_overwrites_existing_row(db: AsyncSession) -> None:
    await cache_set("most_traded", {"v": 1}, ttl=300, db=db)
    await cache_set("most_traded", {"v": 2}, ttl=300, db=db)
    memory_cache_clear()

    assert await cache_get("most_traded", db) == {"v": 2}
    assert await _row_count(db, "most_traded") == 1  # one row, not two


async def test_invalidate_clears_both_layers(db: AsyncSession) -> None:
    await cache_set("news:BBCA", {"headline": "x"}, ttl=900, db=db)
    await cache_invalidate("news:BBCA", db)

    assert _memory.get("news:BBCA") is None
    assert await _row_count(db, "news:BBCA") == 0
    assert await cache_get("news:BBCA", db) is None  # now a miss
    assert cache_stats()["invalidations"] == 1


async def test_list_payloads_round_trip_through_l2(db: AsyncSession) -> None:
    payload = [{"symbol": "BBCA", "volume": 15000000}, {"symbol": "BMRI", "volume": 25000000}]
    await cache_set("most_traded", payload, ttl=300, db=db)
    memory_cache_clear()

    assert await cache_get("most_traded", db) == payload


async def test_stats_track_hit_rate_and_credits_saved(db: AsyncSession) -> None:
    await cache_set("idx_total", {"close": 7250}, ttl=600, db=db)
    memory_cache_clear()

    await cache_get("idx_total", db)  # L2 hit
    await cache_get("idx_total", db)  # L1 hit (repopulated above)
    await cache_get("unknown", db)  # miss

    stats = cache_stats()
    assert stats["l1_hits"] == 1
    assert stats["l2_hits"] == 1
    assert stats["hits"] == 2
    assert stats["misses"] == 1
    assert stats["credits_saved"] == 2  # each hit avoided one Sectors API call
    assert stats["hit_rate"] == round(2 / 3, 4)
