"""Two-layer cache: in-memory dict (L1) + PostgreSQL sectors_cache table (L2).

Lookup order: L1 → L2 → Sectors API. Each cache hit avoids spending an API credit.
"""

from __future__ import annotations

import json
import time
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


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


async def cache_get(key: str, db: AsyncSession) -> Any | None:
    """Look up key in L1, then L2. Returns None on miss."""
    hit = _memory.get(key)
    if hit is not None:
        return hit

    row = (
        await db.execute(
            text("SELECT data, ttl, cached_at FROM sectors_cache WHERE cache_key = :key"),
            {"key": key},
        )
    ).first()

    if row is None:
        return None

    data_json, ttl, cached_at = row
    elapsed = time.time() - cached_at.timestamp()
    if elapsed > ttl:
        await db.execute(
            text("DELETE FROM sectors_cache WHERE cache_key = :key"),
            {"key": key},
        )
        await db.commit()
        return None

    data = json.loads(data_json) if isinstance(data_json, str) else data_json
    _memory.set(key, data, ttl)
    return data


async def cache_set(key: str, data: Any, ttl: int, db: AsyncSession) -> None:
    """Write to both L1 and L2."""
    _memory.set(key, data, ttl)

    data_json = json.dumps(data)
    await db.execute(
        text(
            "INSERT INTO sectors_cache (cache_key, data, ttl, cached_at) "
            "VALUES (:key, :data, :ttl, NOW()) "
            "ON CONFLICT (cache_key) DO UPDATE "
            "SET data = :data, ttl = :ttl, cached_at = NOW()"
        ),
        {"key": key, "data": data_json, "ttl": ttl},
    )
    await db.commit()


async def cache_invalidate(key: str, db: AsyncSession) -> None:
    """Remove from both layers."""
    _memory.invalidate(key)
    await db.execute(
        text("DELETE FROM sectors_cache WHERE cache_key = :key"),
        {"key": key},
    )
    await db.commit()


def memory_cache_clear() -> None:
    """Clear L1 only (useful on server restart)."""
    _memory.clear()


def memory_cache_stats() -> dict[str, int]:
    """Return L1 stats for debugging."""
    return {"l1_entries": _memory.size}
