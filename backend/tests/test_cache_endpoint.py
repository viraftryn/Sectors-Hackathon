"""Tests for GET /api/cache/stats."""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.cache import _utcnow
from app.db.database import get_db
from app.main import app
from tests.conftest import SQLITE_CACHE_DDL, make_sqlite_engine

_EXPECTED_KEYS = {
    "l1_hits",
    "l2_hits",
    "hits",
    "misses",
    "lookups",
    "hit_rate",
    "credits_saved",
    "sets",
    "invalidations",
    "l1_entries",
    "l2_entries",
    "mock_mode",
}


def test_cache_stats_endpoint_degrades_gracefully_without_db() -> None:
    async def _broken_db():
        class _Session:
            async def execute(self, *args: object, **kwargs: object) -> None:
                raise RuntimeError("db unavailable")

        yield _Session()

    app.dependency_overrides[get_db] = _broken_db
    try:
        with TestClient(app) as client:
            resp = client.get("/api/cache/stats")
    finally:
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    body = resp.json()
    assert _EXPECTED_KEYS <= set(body)
    assert body["l2_entries"] is None  # DB down, but endpoint still returns metrics
    assert body["credits_saved"] == body["hits"]


def test_cache_stats_endpoint_reports_l2_row_count() -> None:
    engine = make_sqlite_engine()
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    state = {"ready": False}

    async def _sqlite_db():
        if not state["ready"]:
            async with engine.begin() as conn:
                await conn.execute(text(SQLITE_CACHE_DDL))
                await conn.execute(
                    text(
                        "INSERT INTO sectors_cache (cache_key, data, ttl, cached_at) "
                        "VALUES ('company_report:BBCA', '{}', 300, :t)"
                    ),
                    {"t": _utcnow()},
                )
            state["ready"] = True
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = _sqlite_db
    try:
        with TestClient(app) as client:
            resp = client.get("/api/cache/stats")
    finally:
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    assert resp.json()["l2_entries"] == 1
