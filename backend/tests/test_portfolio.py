from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import settings
from app.db.database import get_db
from app.main import app
from app.mock_data.fixtures import get_mock_response
from tests.conftest import SQLITE_CACHE_DDL, make_sqlite_engine

# Mirrors supabase/migrations/*_invelio_schema.sql for the tables portfolio touches.
PORTFOLIO_DDL = [
    SQLITE_CACHE_DDL,
    """CREATE TABLE stocks (ticker VARCHAR(10) PRIMARY KEY, symbol VARCHAR(15) NOT NULL,
        name VARCHAR(200) NOT NULL)""",
    """CREATE TABLE user_installations (device_id VARCHAR(64) PRIMARY KEY,
        created_at TIMESTAMP NOT NULL, last_active_at TIMESTAMP NOT NULL)""",
    """CREATE TABLE user_holdings (id VARCHAR(36) PRIMARY KEY,
        device_id VARCHAR(64) NOT NULL REFERENCES user_installations(device_id),
        ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker), stock_name VARCHAR(200),
        market VARCHAR(20) NOT NULL DEFAULT 'IDX', currency VARCHAR(10) NOT NULL DEFAULT 'IDR',
        shares NUMERIC NOT NULL CHECK (shares > 0),
        price_per_share NUMERIC NOT NULL CHECK (price_per_share > 0),
        total_invested NUMERIC NOT NULL, buy_date TIMESTAMP NOT NULL,
        created_at TIMESTAMP NOT NULL, updated_at TIMESTAMP NOT NULL)""",
]
A = {"X-Device-Id": "device-a"}
B = {"X-Device-Id": "device-b"}


def last_close(ticker: str) -> float:
    rows = get_mock_response("companies_list")["results"]
    row = next(r for r in rows if r["symbol"] == f"{ticker}.JK")
    return float(row["query_values"]["last_close_price"])


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
                for ddl in PORTFOLIO_DDL:
                    await session.execute(text(ddl))
                for t in settings.tracked_tickers:
                    await session.execute(
                        text("INSERT INTO stocks VALUES (:t, :s, :n)"),
                        {"t": t, "s": f"{t}.JK", "n": f"{t} name"},
                    )
                await session.commit()
                ready = True
            yield session

    app.dependency_overrides[get_db] = _sqlite_db
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_db, None)


def test_device_header_is_required(client: TestClient) -> None:
    assert client.get("/api/portfolio").status_code == 400


def test_add_lot_from_total_invested(client: TestClient) -> None:
    body = {"ticker": "bbca.jk", "price_per_share": 6000, "total_invested": 600000}
    lot = client.post("/api/portfolio/lots", json=body, headers=A)
    assert lot.status_code == 201
    assert lot.json()["ticker"] == "BBCA"
    assert lot.json()["shares"] == 100
    assert lot.json()["stock_name"] == "BBCA name"


def test_rejects_untracked_ticker_and_missing_size(client: TestClient) -> None:
    goto = {"ticker": "GOTO", "price_per_share": 50, "shares": 100}
    assert client.post("/api/portfolio/lots", json=goto, headers=A).status_code == 422
    no_size = {"ticker": "BBCA", "price_per_share": 6000}
    assert client.post("/api/portfolio/lots", json=no_size, headers=A).status_code == 422


def test_summary_groups_lots_and_uses_latest_price(client: TestClient) -> None:
    client.post(
        "/api/portfolio/lots",
        json={"ticker": "BBCA", "price_per_share": 6000, "shares": 100},
        headers=A,
    )
    client.post(
        "/api/portfolio/lots",
        json={"ticker": "BBCA", "price_per_share": 7000, "shares": 100},
        headers=A,
    )
    client.post(
        "/api/portfolio/lots",
        json={"ticker": "TLKM", "price_per_share": 3000, "shares": 200},
        headers=B,
    )

    summary = client.get("/api/portfolio", headers=A).json()
    assert [p["ticker"] for p in summary["positions"]] == ["BBCA"]
    bbca = summary["positions"][0]
    price = last_close("BBCA")
    assert bbca["shares"] == 200
    assert bbca["avg_buy_price"] == 6500
    assert bbca["current_price"] == price
    assert bbca["pnl"] == round(200 * price - 1_300_000, 2)
    assert summary["total_cost"] == 1_300_000


def test_delete_lot_only_for_owner(client: TestClient) -> None:
    lot = client.post(
        "/api/portfolio/lots",
        json={"ticker": "ASII", "price_per_share": 5000, "shares": 10},
        headers=A,
    ).json()
    assert client.delete(f"/api/portfolio/lots/{lot['id']}", headers=B).status_code == 404
    assert client.delete(f"/api/portfolio/lots/{lot['id']}", headers=A).status_code == 204
    assert client.get("/api/portfolio/lots", headers=A).json() == {"lots": []}


def test_client_generated_id_is_kept(client: TestClient) -> None:
    lot_id = "3f2b8c1e-5d4a-4b7e-9c1a-2e6f8d0a1b2c"
    body = {"id": lot_id, "ticker": "UNVR", "price_per_share": 1600, "shares": 50}
    assert client.post("/api/portfolio/lots", json=body, headers=A).json()["id"] == lot_id
    assert client.get("/api/portfolio/lots", headers=A).json()["lots"][0]["id"] == lot_id
