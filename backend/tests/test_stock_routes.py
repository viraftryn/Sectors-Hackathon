from fastapi.testclient import TestClient

from app.config import settings


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
