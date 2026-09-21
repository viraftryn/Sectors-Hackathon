"""Sectors Financial API v2 client. Every call costs credits, see docs.sectors.app."""

from __future__ import annotations

import asyncio
import logging
from datetime import date, timedelta
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

SCREENER_FIELDS = (
    "pe_ttm",
    "pb_mrq",
    "roe_ttm",
    "der_mrq",
    "yield_ttm",
    "daily_close_change",
    "last_close_price",
    "52_w_high_price",
    "52_w_low_price",
)
SUBSECTOR_SECTIONS = ("statistics", "market_cap", "stability", "growth")
REPORT_SECTIONS = ("overview", "valuation")
HISTORY_DAYS = 90
LIST_LIMIT = 30
TOP_N = 5

_MAX_CONCURRENT = 4


class SectorsError(Exception):
    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(f"Sectors API {status_code}: {detail}")
        self.status_code = status_code


def bare_symbol(symbol: str) -> str:
    return symbol.upper().removesuffix(".JK")


def screener_where(symbols: list[str]) -> str:
    # Null fields fail comparisons, so OR them to keep rows while still returning every field.
    listed = ",".join(f"'{bare_symbol(s)}.JK'" for s in symbols)
    any_value = " or ".join(f"{f} > -1000000" for f in SCREENER_FIELDS)
    return f"symbol in [{listed}] and sector != '' and sub_sector != '' and ({any_value})"


def _history_start() -> str:
    return (date.today() - timedelta(days=HISTORY_DAYS)).isoformat()


class SectorsClient:
    """Real API client. CachedSectorsClient decides whether it is called at all."""

    request_count = 0
    _semaphore = asyncio.Semaphore(_MAX_CONCURRENT)

    def __init__(self, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self._base_url = settings.sectors_base_url
        self._headers = {"Authorization": settings.sectors_api_key}
        self._transport = transport

    async def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        params = {k: v for k, v in (params or {}).items() if v is not None}
        async with self._semaphore, httpx.AsyncClient(transport=self._transport) as client:
            for attempt in range(2):
                response = await client.get(
                    f"{self._base_url}{path}", headers=self._headers, params=params, timeout=30.0
                )
                if response.status_code == 429 and attempt == 0:
                    await asyncio.sleep(float(response.headers.get("Retry-After", 2)))
                    continue
                break
        SectorsClient.request_count += 1
        logger.info("Sectors %s %s -> %s", path, params, response.status_code)
        if response.status_code >= 400:
            raise SectorsError(response.status_code, response.text[:200])
        return response.json()

    # --- Fundamental / Company data ---

    async def get_company_report(self, ticker: str) -> Any:
        return await self._get(
            f"/company/report/{bare_symbol(ticker)}/", {"sections": ",".join(REPORT_SECTIONS)}
        )

    async def list_companies(self) -> Any:
        tickers = settings.tracked_tickers
        return await self._get(
            "/companies/",
            {
                "where": screener_where(tickers),
                "order_by": "-market_cap",
                "limit": len(tickers),
                "include_query_values": "true",
            },
        )

    # --- Price / Trending data ---

    async def get_daily_prices(self, ticker: str) -> Any:
        return await self._get(f"/daily/{bare_symbol(ticker)}/", {"start": _history_start()})

    async def get_most_traded(self) -> Any:
        return await self._get("/most-traded/", {"n_stock": TOP_N})

    async def get_top_companies(self) -> Any:
        return await self._get(
            "/companies/top-changes/",
            {"classifications": "top_gainers,top_losers", "periods": "1d", "n_stock": TOP_N},
        )

    # --- Market index ---

    async def get_idx_total(self) -> Any:
        return await self._get("/idx-total/", {"start": _history_start()})

    async def get_ihsg(self) -> Any:
        return await self._get("/index-daily/ihsg/", {"start": _history_start()})

    async def get_foreign_flow(self, ticker: str = "IHSG") -> Any:
        return await self._get(f"/foreign-flow/{bare_symbol(ticker)}/")

    # --- Sector reports ---

    async def get_sector_report(self, sub_sector: str) -> Any:
        return await self._get(
            f"/subsector/report/{sub_sector}/", {"sections": ",".join(SUBSECTOR_SECTIONS)}
        )

    # --- News / Filings ---

    async def get_news(self, ticker: str | None = None) -> Any:
        symbols = bare_symbol(ticker) if ticker else None
        return await self._get("/news/", {"symbols": symbols, "limit": LIST_LIMIT})

    async def get_news_filings(self, ticker: str | None = None) -> Any:
        symbol = bare_symbol(ticker) if ticker else None
        return await self._get("/filings/", {"symbol": symbol, "limit": LIST_LIMIT})
