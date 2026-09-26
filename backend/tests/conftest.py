"""Shared pytest fixtures.

The two-layer cache's L2 path is exercised against an in-memory SQLite database
(via aiosqlite) so the real cache_get/cache_set SQL runs in tests without needing a
live PostgreSQL. The cache SQL is written to be portable (no NOW(), plain upsert), so
the same code paths run here and against Supabase.
"""

from __future__ import annotations

import sqlite3
from collections.abc import AsyncGenerator
from datetime import datetime

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.cache import memory_cache_clear, reset_cache_metrics
from app.main import app

# Store datetimes as ISO strings on SQLite (avoids the Python 3.12 deprecation of the
# default sqlite3 datetime adapter). Matches what _coerce_dt parses back.
sqlite3.register_adapter(datetime, lambda dt: dt.isoformat(sep=" "))

# SQLite stand-in for the sectors_cache table (JSONB -> TEXT; both hold the JSON string).
SQLITE_CACHE_DDL = """
CREATE TABLE IF NOT EXISTS sectors_cache (
    cache_key VARCHAR(200) PRIMARY KEY,
    data TEXT NOT NULL,
    ttl INTEGER NOT NULL,
    cached_at TIMESTAMP NOT NULL
)
"""

SQLITE_INSIGHTS_DDL = """
CREATE TABLE IF NOT EXISTS stock_ai_insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ticker VARCHAR(10) NOT NULL,
    analysis_type VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    content TEXT NOT NULL,
    generated_date DATE NOT NULL,
    created_at TIMESTAMP NOT NULL,
    UNIQUE (ticker, analysis_type, generated_date)
)
"""


def make_sqlite_engine():
    """Fresh in-memory SQLite engine that survives across connections (StaticPool)."""
    return create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def _reset_cache() -> None:
    """Isolate the process-global L1 store + metrics between tests."""
    memory_cache_clear()
    reset_cache_metrics()
    yield
    memory_cache_clear()
    reset_cache_metrics()


@pytest_asyncio.fixture
async def db() -> AsyncGenerator[AsyncSession, None]:
    """An AsyncSession backed by an in-memory SQLite DB with the sectors_cache table."""
    engine = make_sqlite_engine()
    async with engine.begin() as conn:
        await conn.execute(text(SQLITE_CACHE_DDL))
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as session:
        yield session
    await engine.dispose()
