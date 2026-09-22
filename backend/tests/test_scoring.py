from collections.abc import AsyncIterator, Iterator
from typing import Any

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.agents import scoring
from app.agents.scoring import (
    fundamental_score,
    recommend,
    risk_score,
    run_scoring,
    scale,
    sentiment_score,
)
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.llm import LLMError
from app.config import settings
from app.db.database import get_db
from app.main import app
from tests.conftest import SQLITE_CACHE_DDL, make_sqlite_engine

# Mirrors supabase/migrations/*_invelio_schema.sql for the tables scoring touches.
SQLITE_SCORE_DDL = [
    SQLITE_CACHE_DDL,
    """CREATE TABLE IF NOT EXISTS stocks (
        ticker VARCHAR(10) PRIMARY KEY, symbol VARCHAR(15) NOT NULL, name VARCHAR(200) NOT NULL,
        sector VARCHAR(100), sub_sector VARCHAR(100), price NUMERIC NOT NULL DEFAULT 0,
        change_pct NUMERIC, market_cap NUMERIC, pe_ttm NUMERIC, pb_mrq NUMERIC, roe_ttm NUMERIC,
        der_mrq NUMERIC, yield_ttm NUMERIC, week52_high NUMERIC, week52_low NUMERIC,
        updated_at TIMESTAMP)""",
    """CREATE TABLE IF NOT EXISTS stock_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT, ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker),
        fundamental_score FLOAT, macro_score FLOAT, sector_score FLOAT, risk_score FLOAT,
        sentiment_score FLOAT, overall_score FLOAT, recommendation VARCHAR(10), reasoning TEXT,
        scored_at TIMESTAMP)""",
]


async def fake_llm(prompt: str, system: str) -> Any:
    tickers = [line.split(" ")[0] for line in prompt.splitlines()[2:]]
    return [
        {"ticker": t, "recommendation": "HOLD", "reasoning": f"{t} looks balanced."}
        for t in tickers
    ]


async def failing_llm(prompt: str, system: str) -> Any:
    raise LLMError("offline")


@pytest_asyncio.fixture
async def mock_db(monkeypatch: pytest.MonkeyPatch) -> AsyncIterator[AsyncSession]:
    monkeypatch.setattr(settings, "use_mock_data", True)
    engine = make_sqlite_engine()
    async with engine.begin() as conn:
        for ddl in SQLITE_SCORE_DDL:
            await conn.execute(text(ddl))
    async with async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


def test_scale_clamps_and_inverts() -> None:
    assert scale(0.1, 0, 0.2) == 50
    assert scale(1.0, 0, 0.2) == 100
    assert scale(30, 25, 8) == 0
    assert scale(8, 25, 8) == 100


def test_fundamental_skips_missing_der_and_zeroes_negative_pe() -> None:
    bank = {"pe_ttm": 10, "pb_mrq": 1, "roe_ttm": 0.2, "der_mrq": None, "yield_ttm": 0.08}
    assert fundamental_score(bank, sector_median_pe=10) > 80
    loss_maker = {"pe_ttm": -5, "pb_mrq": 5, "roe_ttm": -0.1, "der_mrq": 3, "yield_ttm": 0}
    assert fundamental_score(loss_maker, None) == 0


def test_sentiment_uses_news_tags_and_insider_flow() -> None:
    bullish = [{"tags": ["Bullish"]}, {"tags": ["Bullish"]}]
    assert sentiment_score(bullish, []) == 100
    assert sentiment_score([], []) == 50
    sells = [{"transaction_type": "sell", "transaction_value": 1e9}]
    assert sentiment_score(bullish, sells) == 70


def test_risk_prefers_calm_prices() -> None:
    calm = [100 + (i % 2) * 0.2 for i in range(40)]
    wild = [100 * (1.2 if i % 2 else 0.8) for i in range(40)]
    assert risk_score(calm) > risk_score(wild)


def test_recommend_thresholds() -> None:
    assert recommend(70) == "BUY"
    assert recommend(50) == "HOLD"
    assert recommend(35) == "SELL"


async def test_graph_scores_all_tracked_tickers(mock_db: AsyncSession) -> None:
    results = await run_scoring(CachedSectorsClient(mock_db), fake_llm)
    assert {r["ticker"] for r in results} == set(settings.tracked_tickers)
    scores = [r["overall_score"] for r in results]
    assert scores == sorted(scores, reverse=True)
    assert all(0 <= s <= 100 for s in scores)
    assert all(r["reasoning"].endswith("looks balanced.") for r in results)


async def test_graph_falls_back_when_llm_fails(mock_db: AsyncSession) -> None:
    results = await run_scoring(CachedSectorsClient(mock_db), failing_llm)
    top = results[0]
    assert top["recommendation"] == recommend(top["overall_score"])
    assert "Strongest factor" in top["reasoning"]


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    monkeypatch.setattr(settings, "use_mock_data", True)
    monkeypatch.setattr(scoring, "generate_json", fake_llm)
    engine = make_sqlite_engine()
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    ready = False

    async def _sqlite_db():  # type: ignore[no-untyped-def]
        nonlocal ready
        async with factory() as session:
            if not ready:
                for ddl in SQLITE_SCORE_DDL:
                    await session.execute(text(ddl))
                ready = True
            yield session

    app.dependency_overrides[get_db] = _sqlite_db
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_db, None)


def test_recommendations_empty_before_first_run(client: TestClient) -> None:
    body = client.get("/api/recommendations").json()
    assert body == {"scored_at": None, "recommendations": []}


def test_run_then_read_recommendations(client: TestClient) -> None:
    run = client.post("/api/scoring/run")
    assert run.status_code == 200
    recs = run.json()["recommendations"]
    assert len(recs) == len(settings.tracked_tickers)
    assert {"fundamental", "macro", "sector", "risk", "sentiment"} == set(recs[0]["scores"])
    assert client.get("/api/recommendations").json() == run.json()


def test_run_is_skipped_within_min_interval(client: TestClient) -> None:
    first = client.post("/api/scoring/run").json()
    second = client.post("/api/scoring/run").json()
    assert first["scored_at"] == second["scored_at"]
