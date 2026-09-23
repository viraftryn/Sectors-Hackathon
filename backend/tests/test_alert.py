"""Tests for the Alert Agent."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest

from app.agents.alert import (
    PRICE_CHANGE_HIGH,
    PRICE_CHANGE_MEDIUM,
    AlertAgent,
    AlertState,
)


def _make_mover(
    symbol: str,
    name: str,
    change: float,
    price: float = 5000,
    category: str = "top_gainers",
) -> dict:
    return {
        "symbol": symbol,
        "name": name,
        "price_change": change,
        "last_close_price": price,
        "latest_close_date": "2026-09-23",
        "_category": category,
    }


def _make_article(title: str, symbols: list[str], tags: list[str]) -> dict:
    return {
        "title": title,
        "body": "mock body",
        "source": "https://example.com",
        "timestamp": "2026-09-23T06:00:00",
        "tags": tags,
        "symbols": symbols,
    }


# -- Unit: _detect_anomalies -------------------------------------------------


@pytest.mark.asyncio
async def test_detect_price_spike_high():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [_make_mover("ANTM.JK", "Aneka Tambang", 0.08)],
        "most_traded": [],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert result["anomalies"][0]["severity"] == "high"
    assert result["anomalies"][0]["alert_type"] == "price_spike"
    assert "ANTM" in result["anomalies"][0]["ticker"]


@pytest.mark.asyncio
async def test_detect_price_spike_medium():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [_make_mover("BBCA.JK", "BCA", 0.04)],
        "most_traded": [],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert result["anomalies"][0]["severity"] == "medium"


@pytest.mark.asyncio
async def test_no_anomaly_below_threshold():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [_make_mover("BBCA.JK", "BCA", 0.01)],
        "most_traded": [],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 0


@pytest.mark.asyncio
async def test_detect_volume_surge():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [],
        "most_traded": [
            {
                "symbol": "BBRI.JK",
                "company_name": "PT Bank Rakyat Indonesia",
                "volume": 200_000_000,
                "price": 3310,
            },
        ],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert result["anomalies"][0]["alert_type"] == "volume_surge"
    assert result["anomalies"][0]["severity"] == "medium"
    assert "most-traded" in result["anomalies"][0]["message"]


@pytest.mark.asyncio
async def test_volume_surge_skips_untracked_ticker():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [],
        "most_traded": [
            {"symbol": "GOTO.JK", "company_name": "GoTo", "volume": 500_000_000, "price": 50},
        ],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 0


@pytest.mark.asyncio
async def test_volume_surge_skipped_if_already_price_spike():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [_make_mover("ANTM.JK", "Aneka Tambang", 0.06)],
        "most_traded": [
            {
                "symbol": "ANTM.JK",
                "company_name": "Aneka Tambang",
                "volume": 100_000_000,
                "price": 3340,
            },
        ],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert result["anomalies"][0]["alert_type"] == "price_spike"


@pytest.mark.asyncio
async def test_detect_negative_sentiment():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [],
        "most_traded": [],
        "news_articles": [
            _make_article("BBCA fraud case", ["BBCA.JK"], ["Bearish", "Fraud"]),
            _make_article("BBCA lawsuit", ["BBCA.JK"], ["Lawsuit"]),
        ],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert result["anomalies"][0]["alert_type"] == "sentiment_shift"
    assert result["anomalies"][0]["ticker"] == "BBCA"


@pytest.mark.asyncio
async def test_sentiment_enriches_existing_price_spike():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [
            _make_mover("ANTM.JK", "Aneka Tambang", -0.06, category="top_losers"),
        ],
        "most_traded": [],
        "news_articles": [
            _make_article("ANTM scandal", ["ANTM.JK"], ["Scandal"]),
        ],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert result["anomalies"][0]["alert_type"] == "price_spike"
    assert "berita negatif" in result["anomalies"][0]["message"]


@pytest.mark.asyncio
async def test_ignores_positive_news():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [],
        "most_traded": [],
        "news_articles": [
            _make_article("BBCA great quarter", ["BBCA.JK"], ["Bullish"]),
        ],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 0


@pytest.mark.asyncio
async def test_deduplicates_tickers():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [
            _make_mover("ANTM.JK", "Aneka Tambang", 0.06),
            _make_mover("ANTM.JK", "Aneka Tambang", 0.07),
        ],
        "most_traded": [],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1


@pytest.mark.asyncio
async def test_negative_change_detected():
    agent = AlertAgent(db=AsyncMock())
    state: AlertState = {
        "top_movers": [
            _make_mover("BBNI.JK", "BNI", -0.05, category="top_losers"),
        ],
        "most_traded": [],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._detect_anomalies(state)
    assert len(result["anomalies"]) == 1
    assert "turun" in result["anomalies"][0]["message"]


# -- Unit: _fetch_market_data ------------------------------------------------


@pytest.mark.asyncio
async def test_fetch_market_data():
    agent = AlertAgent(db=AsyncMock())
    mock_top = {
        "top_gainers": {"1d": [_make_mover("ANTM.JK", "Aneka Tambang", 0.08)]},
        "top_losers": {"1d": []},
    }
    mock_traded = {
        "2026-09-23": [{"symbol": "BBRI.JK", "company_name": "BRI", "volume": 100, "price": 3300}]
    }
    mock_news = {"results": [_make_article("test", ["BBCA.JK"], ["Bullish"])]}
    agent._client = AsyncMock()
    agent._client.get_top_companies = AsyncMock(return_value=mock_top)
    agent._client.get_most_traded = AsyncMock(return_value=mock_traded)
    agent._client.get_news = AsyncMock(return_value=mock_news)

    state: AlertState = {
        "top_movers": [],
        "most_traded": [],
        "news_articles": [],
        "anomalies": [],
        "alerts_created": 0,
    }
    result = await agent._fetch_market_data(state)
    assert len(result["top_movers"]) == 1
    assert len(result["most_traded"]) == 1
    assert len(result["news_articles"]) == 1


# -- Constants ---------------------------------------------------------------


def test_threshold_ordering():
    assert PRICE_CHANGE_HIGH > PRICE_CHANGE_MEDIUM > 0
