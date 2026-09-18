"""Tests to verify mock data fixtures are valid and usable."""

from app.mock_data.fixtures import (
    COMPANIES_LIST,
    COMPANY_REPORT_BBCA,
    DAILY_PRICES_BBCA,
    IDX_TOTAL,
    MOCK_RESPONSES,
    MOST_TRADED,
    NEWS_BBCA,
    SECTOR_REPORT,
    TOP_COMPANIES,
)


def test_company_report_has_required_fields() -> None:
    for field in ["symbol", "company_name", "sector", "pb_ratio", "pe_ratio", "roe"]:
        assert field in COMPANY_REPORT_BBCA, f"Missing {field}"


def test_daily_prices_is_list() -> None:
    assert len(DAILY_PRICES_BBCA) > 0
    assert "close" in DAILY_PRICES_BBCA[0]
    assert "volume" in DAILY_PRICES_BBCA[0]


def test_companies_list_has_entries() -> None:
    assert len(COMPANIES_LIST) >= 3
    assert all("symbol" in c for c in COMPANIES_LIST)


def test_idx_total_has_index() -> None:
    assert IDX_TOTAL["index"] == "IHSG"
    assert "close" in IDX_TOTAL


def test_mock_responses_keys_match_cache_keys() -> None:
    assert "company_report:BBCA" in MOCK_RESPONSES
    assert "daily_prices:BBCA" in MOCK_RESPONSES
    assert "most_traded" in MOCK_RESPONSES
    assert "idx_total" in MOCK_RESPONSES


def test_news_has_sentiment() -> None:
    assert len(NEWS_BBCA) > 0
    assert "sentiment" in NEWS_BBCA[0]


def test_most_traded_has_volume() -> None:
    assert all("volume" in t for t in MOST_TRADED)


def test_top_companies_has_change() -> None:
    assert all("change_pct" in t for t in TOP_COMPANIES)


def test_sector_report_has_performance() -> None:
    assert all("performance_1d" in s for s in SECTOR_REPORT)
