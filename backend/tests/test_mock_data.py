"""Tests to verify mock data fixtures are valid and usable (Sectors v2 shapes)."""

from app.config import settings
from app.mock_data.fixtures import MOCK_RESPONSES, get_mock_response


def test_every_tracked_ticker_has_fixtures() -> None:
    for ticker in settings.tracked_tickers:
        for prefix in ["company_report", "daily_prices", "news", "news_filings", "foreign_flow"]:
            assert f"{prefix}:{ticker}" in MOCK_RESPONSES, f"Missing {prefix}:{ticker}"


def test_market_wide_keys_exist() -> None:
    for key in ["companies_list", "most_traded", "top_companies", "idx_total", "ihsg"]:
        assert key in MOCK_RESPONSES, f"Missing {key}"


def test_companies_list_has_ratios() -> None:
    rows = get_mock_response("companies_list")["results"]
    assert {r["symbol"] for r in rows} == {f"{t}.JK" for t in settings.tracked_tickers}
    for field in ["pe_ttm", "pb_mrq", "roe_ttm", "der_mrq", "last_close_price", "sub_sector"]:
        assert field in rows[0]["query_values"], f"Missing {field}"


def test_company_report_has_sections() -> None:
    report = get_mock_response("company_report:BBCA")
    assert report["symbol"] == "BBCA.JK"
    assert "overview" in report and "valuation" in report


def test_daily_prices_is_list() -> None:
    daily = get_mock_response("daily_prices:BBCA")
    assert len(daily) > 20
    assert {"date", "close", "volume"} <= set(daily[0])


def test_news_has_sentiment_tags() -> None:
    articles = get_mock_response("news:all")["results"]
    assert any({"Bullish", "Bearish"} & set(a["tags"]) for a in articles)


def test_ticker_news_only_mentions_ticker() -> None:
    articles = get_mock_response("news:BBCA")["results"]
    assert all("BBCA.JK" in a["symbols"] for a in articles)


def test_most_traded_has_volume() -> None:
    days = get_mock_response("most_traded")
    assert all("volume" in t for rows in days.values() for t in rows)


def test_top_companies_has_change() -> None:
    movers = get_mock_response("top_companies")
    assert all("price_change" in t for t in movers["top_gainers"]["1d"])


def test_sector_report_has_stability() -> None:
    assert "stability" in get_mock_response("sector_report:banks")
