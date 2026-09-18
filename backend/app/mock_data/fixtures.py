"""Mock Sectors API responses for development — zero credits spent.

Switch to real API only for integration testing and demo day.
"""

COMPANY_REPORT_BBCA: dict = {
    "symbol": "BBCA",
    "company_name": "PT Bank Central Asia Tbk",
    "sector": "Financials",
    "sub_sector": "Banks",
    "market_cap": 1200000000000000,
    "last_close_price": 9800,
    "pb_ratio": 4.5,
    "pe_ratio": 22.3,
    "roe": 21.5,
    "der": 5.2,
    "revenue": 90000000000000,
    "net_income": 48000000000000,
    "dividend_yield": 1.8,
}

COMPANY_REPORT_BMRI: dict = {
    "symbol": "BMRI",
    "company_name": "PT Bank Mandiri (Persero) Tbk",
    "sector": "Financials",
    "sub_sector": "Banks",
    "market_cap": 600000000000000,
    "last_close_price": 6350,
    "pb_ratio": 2.1,
    "pe_ratio": 10.5,
    "roe": 19.8,
    "der": 5.8,
    "revenue": 75000000000000,
    "net_income": 42000000000000,
    "dividend_yield": 3.2,
}

DAILY_PRICES_BBCA: list[dict] = [
    {
        "date": "2026-09-18",
        "close": 9800,
        "open": 9750,
        "high": 9850,
        "low": 9700,
        "volume": 15000000,
    },
    {
        "date": "2026-09-17",
        "close": 9750,
        "open": 9700,
        "high": 9800,
        "low": 9650,
        "volume": 12000000,
    },
    {
        "date": "2026-09-16",
        "close": 9700,
        "open": 9650,
        "high": 9750,
        "low": 9600,
        "volume": 13000000,
    },
]

COMPANIES_LIST: list[dict] = [
    {"symbol": "BBCA", "company_name": "PT Bank Central Asia Tbk", "sector": "Financials"},
    {"symbol": "BMRI", "company_name": "PT Bank Mandiri (Persero) Tbk", "sector": "Financials"},
    {
        "symbol": "TLKM",
        "company_name": "PT Telkom Indonesia Tbk",
        "sector": "Communication Services",
    },
    {
        "symbol": "ASII",
        "company_name": "PT Astra International Tbk",
        "sector": "Consumer Discretionary",
    },
    {"symbol": "UNVR", "company_name": "PT Unilever Indonesia Tbk", "sector": "Consumer Staples"},
]

MOST_TRADED: list[dict] = [
    {"symbol": "BBCA", "volume": 15000000, "value": 147000000000},
    {"symbol": "BMRI", "volume": 25000000, "value": 158750000000},
    {"symbol": "TLKM", "volume": 30000000, "value": 99000000000},
]

TOP_COMPANIES: list[dict] = [
    {"symbol": "BBCA", "change_pct": 2.1, "close": 9800},
    {"symbol": "ASII", "change_pct": 1.8, "close": 5250},
    {"symbol": "TLKM", "change_pct": -0.5, "close": 3300},
]

IDX_TOTAL: dict = {
    "index": "IHSG",
    "close": 7250.5,
    "change": 45.2,
    "change_pct": 0.63,
    "volume": 12500000000,
    "date": "2026-09-18",
}

SECTOR_REPORT: list[dict] = [
    {"sector": "Financials", "performance_1d": 0.8, "performance_1w": 2.1, "performance_1m": 5.3},
    {
        "sector": "Communication Services",
        "performance_1d": -0.2,
        "performance_1w": 1.0,
        "performance_1m": 3.1,
    },
    {
        "sector": "Consumer Staples",
        "performance_1d": 0.5,
        "performance_1w": 0.8,
        "performance_1m": 1.2,
    },
]

NEWS_BBCA: list[dict] = [
    {
        "title": "BBCA Reports Record Q3 2026 Net Income",
        "source": "Bisnis Indonesia",
        "published_at": "2026-09-18T08:00:00Z",
        "sentiment": "positive",
        "ticker": "BBCA",
    },
    {
        "title": "Bank Indonesia Holds Rates Steady, Banking Sector Stable",
        "source": "CNBC Indonesia",
        "published_at": "2026-09-17T14:30:00Z",
        "sentiment": "neutral",
        "ticker": "BBCA",
    },
]

NEWS_FILINGS_BBCA: list[dict] = [
    {
        "title": "BBCA - Laporan Keuangan Q3 2026",
        "filing_type": "financial_report",
        "published_at": "2026-09-15T10:00:00Z",
        "ticker": "BBCA",
    },
]

MOCK_RESPONSES: dict[str, dict | list] = {
    "company_report:BBCA": COMPANY_REPORT_BBCA,
    "company_report:BMRI": COMPANY_REPORT_BMRI,
    "daily_prices:BBCA": DAILY_PRICES_BBCA,
    "companies_list": COMPANIES_LIST,
    "most_traded": MOST_TRADED,
    "top_companies": TOP_COMPANIES,
    "idx_total": IDX_TOTAL,
    "sector_report": SECTOR_REPORT,
    "news:BBCA": NEWS_BBCA,
    "news_filings:BBCA": NEWS_FILINGS_BBCA,
}
