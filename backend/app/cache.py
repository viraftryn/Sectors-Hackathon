"""Two-layer cache: in-memory dict (L1) + PostgreSQL sectors_cache table (L2).

Lookup order: L1 -> L2 -> Sectors API. Each cache hit avoids spending an API credit,
which is the whole point on a 1,000-credit budget (see implementation plan Section 5).

Timestamps are handled as naive UTC on the Python side and stored in the TIMESTAMP
(without time zone) column, so TTL math is correct regardless of the DB server's
time zone (Supabase runs UTC). We never rely on the DB's NOW(), which keeps the SQL
portable enough to unit-test against SQLite.
"""

from __future__ import annotations

import json
import time
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


def _utcnow() -> datetime:
    """Naive UTC 'now' — matches the TIMESTAMP (without tz) column and epoch math."""
    return datetime.now(UTC).replace(tzinfo=None)


def _coerce_dt(value: datetime | str) -> datetime:
    """Normalize a cached_at value to a naive UTC datetime.

    Postgres/asyncpg returns a datetime; SQLite returns an ISO string. Handle both.
    """
    if isinstance(value, datetime):
        return value.replace(tzinfo=None) if value.tzinfo else value
    parsed = datetime.fromisoformat(value)
    return parsed.replace(tzinfo=None) if parsed.tzinfo else parsed


class _CacheMetrics:
    """Process-wide hit/miss counters — powers /api/cache/stats and credit tracking.

    Each cache hit (L1 or L2) is one Sectors API call we did NOT make, so
    ``credits_saved`` equals total hits. Reset on server restart; that's fine — it's
    an operational gauge for the demo, not persisted state.
    """

    def __init__(self) -> None:
        self.l1_hits = 0
        self.l2_hits = 0
        self.misses = 0
        self.sets = 0
        self.invalidations = 0

    def record_l1_hit(self) -> None:
        self.l1_hits += 1

    def record_l2_hit(self) -> None:
        self.l2_hits += 1

    def record_miss(self) -> None:
        self.misses += 1

    def record_set(self) -> None:
        self.sets += 1

    def record_invalidation(self) -> None:
        self.invalidations += 1

    def reset(self) -> None:
        self.l1_hits = 0
        self.l2_hits = 0
        self.misses = 0
        self.sets = 0
        self.invalidations = 0

    @property
    def total_hits(self) -> int:
        return self.l1_hits + self.l2_hits

    @property
    def total_lookups(self) -> int:
        return self.total_hits + self.misses

    @property
    def hit_rate(self) -> float:
        return self.total_hits / self.total_lookups if self.total_lookups else 0.0

    def snapshot(self) -> dict[str, Any]:
        return {
            "l1_hits": self.l1_hits,
            "l2_hits": self.l2_hits,
            "hits": self.total_hits,
            "misses": self.misses,
            "lookups": self.total_lookups,
            "hit_rate": round(self.hit_rate, 4),
            "credits_saved": self.total_hits,
            "sets": self.sets,
            "invalidations": self.invalidations,
        }


class _MemoryStore:
    """L1 — in-process dict with per-key TTL tracking."""

    def __init__(self) -> None:
        self._store: dict[str, tuple[Any, float, int]] = {}

    def get(self, key: str) -> Any | None:
        entry = self._store.get(key)
        if entry is None:
            return None
        data, cached_at, ttl = entry
        if time.time() - cached_at > ttl:
            del self._store[key]
            return None
        return data

    def set(self, key: str, data: Any, ttl: int) -> None:
        self._store[key] = (data, time.time(), ttl)

    def invalidate(self, key: str) -> None:
        self._store.pop(key, None)

    def clear(self) -> None:
        self._store.clear()

    @property
    def size(self) -> int:
        return len(self._store)


_memory = _MemoryStore()
_metrics = _CacheMetrics()


async def cache_get(key: str, db: AsyncSession | None) -> Any | None:
    """Look up key in L1, then L2. Returns None on miss.

    Note: values are stored via ``cache_set``, which is never called with ``None``,
    so ``None`` unambiguously means "not cached".
    When *db* is ``None`` L2 is skipped (L1-only mode).
    """
    hit = _memory.get(key)
    if hit is not None:
        _metrics.record_l1_hit()
        return hit

    if db is None:
        _metrics.record_miss()
        return None

    row = (
        await db.execute(
            text("SELECT data, ttl, cached_at FROM sectors_cache WHERE cache_key = :key"),
            {"key": key},
        )
    ).first()

    if row is None:
        _metrics.record_miss()
        return None

    data_raw, ttl, cached_at = row
    elapsed = (_utcnow() - _coerce_dt(cached_at)).total_seconds()
    if elapsed > ttl:
        await db.execute(
            text("DELETE FROM sectors_cache WHERE cache_key = :key"),
            {"key": key},
        )
        await db.commit()
        _metrics.record_miss()
        return None

    data = json.loads(data_raw) if isinstance(data_raw, str) else data_raw

    # Promote to L1 with the REMAINING ttl, not the full ttl, so total staleness
    # stays bounded by the configured TTL instead of (L2 age + full L1 ttl).
    remaining = int(ttl - elapsed)
    if remaining > 0:
        _memory.set(key, data, remaining)

    _metrics.record_l2_hit()
    return data


async def cache_set(key: str, data: Any, ttl: int, db: AsyncSession | None) -> None:
    """Write to both L1 and L2.  When *db* is ``None`` only L1 is written."""
    _memory.set(key, data, ttl)

    if db is None:
        _metrics.record_set()
        return

    data_json = json.dumps(data)
    await db.execute(
        text(
            "INSERT INTO sectors_cache (cache_key, data, ttl, cached_at) "
            "VALUES (:key, :data, :ttl, :cached_at) "
            "ON CONFLICT (cache_key) DO UPDATE "
            "SET data = :data, ttl = :ttl, cached_at = :cached_at"
        ),
        {"key": key, "data": data_json, "ttl": ttl, "cached_at": _utcnow()},
    )
    await db.commit()
    _metrics.record_set()


async def cache_invalidate(key: str, db: AsyncSession) -> None:
    """Remove from both layers."""
    _memory.invalidate(key)
    await db.execute(
        text("DELETE FROM sectors_cache WHERE cache_key = :key"),
        {"key": key},
    )
    await db.commit()
    _metrics.record_invalidation()


def memory_cache_clear() -> None:
    """Clear L1 only (useful on server restart or between tests)."""
    _memory.clear()


def reset_cache_metrics() -> None:
    """Zero the hit/miss counters (useful between tests)."""
    _metrics.reset()


def cache_stats() -> dict[str, Any]:
    """Return in-memory cache metrics + L1 size. Requires no DB, always available."""
    return {**_metrics.snapshot(), "l1_entries": _memory.size}
