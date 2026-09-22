from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import SectorsError
from app.config import settings
from app.db.database import get_db
from app.main import app
from tests.conftest import SQLITE_CACHE_DDL, make_sqlite_engine


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    monkeypatch.setattr(settings, "use_mock_data", True)
    engine = make_sqlite_engine()
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    ready = False

    async def _sqlite_db():  # type: ignore[no-untyped-def]
        nonlocal ready
        async with factory() as session:
            if not ready:
                await session.execute(text(SQLITE_CACHE_DDL))
                ready = True
            yield session

    app.dependency_overrides[get_db] = _sqlite_db
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_db, None)


def test_list_stocks(client: TestClient) -> None:
    response = client.get("/api/stocks")
    assert response.status_code == 200
    stocks = response.json()["stocks"]
    assert {s["ticker"] for s in stocks} == set(settings.tracked_tickers)
    bbca = next(s for s in stocks if s["ticker"] == "BBCA")
    assert bbca["sub_sector"] == "Banks"
    assert bbca["price"] > 0


def test_stock_detail(client: TestClient) -> None:
    response = client.get("/api/stock/bbca")
    assert response.status_code == 200
    data = response.json()
    assert data["ticker"] == "BBCA"
    assert data["fundamentals"]["der"] is None
    assert 0 < data["fundamentals"]["roe_pct"] < 100
    assert len(data["prices"]) > 20
    assert data["prices"][-1]["close"] == data["price"]


def test_stock_detail_untracked_ticker(client: TestClient) -> None:
    assert client.get("/api/stock/GOTO").status_code == 404


def test_market_overview(client: TestClient) -> None:
    response = client.get("/api/market-overview")
    assert response.status_code == 200
    data = response.json()
    assert data["ihsg"]["name"] == "IHSG"
    assert len(data["ihsg"]["series"]) > 1
    assert len(data["top_gainers"]) == 5
    assert data["most_traded"]
    assert data["foreign_flow"] is not None


def test_second_request_is_served_from_cache(client: TestClient) -> None:
    client.get("/api/stocks")
    client.get("/api/stocks")
    assert client.get("/api/cache/stats").json()["l1_hits"] >= 1


def test_market_overview_survives_secondary_failures(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def down(self: CachedSectorsClient) -> None:
        raise SectorsError(429, "rate limited")

    monkeypatch.setattr(CachedSectorsClient, "get_top_companies", down)
    monkeypatch.setattr(CachedSectorsClient, "get_most_traded", down)
    response = client.get("/api/market-overview")
    assert response.status_code == 200
    assert response.json()["top_gainers"] == []
    assert response.json()["most_traded"] == []
    assert response.json()["ihsg"]["value"] > 0


def test_status_reports_mock_mode(client: TestClient) -> None:
    body = client.get("/api/status").json()
    assert body["mock_data"] is True
    assert isinstance(body["sectors_api_calls"], int)
