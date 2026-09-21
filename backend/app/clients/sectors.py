"""Sectors Financial API v2 client. Every call costs credits, see docs.sectors.app."""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Protocol

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


class SectorsSource(Protocol):
    async def screen_companies(self, symbols: list[str]) -> dict[str, Any]: ...

    async def get_daily(
        self, symbol: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]: ...

    async def get_index_daily(
        self, index_code: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]: ...

    async def get_subsector_report(self, sub_sector: str) -> dict[str, Any]: ...

    async def get_top_changes(self, period: str = "1d", n_stock: int = 5) -> dict[str, Any]: ...

    async def get_most_traded(self, n_stock: int = 5) -> dict[str, Any]: ...

    async def get_news(
        self, symbols: list[str] | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]: ...

    async def get_filings(
        self, symbol: str | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]: ...

    async def get_foreign_flow(
        self, symbol: str = "IHSG", start: str | None = None, end: str | None = None
    ) -> dict[str, Any]: ...


class SectorsClient:
    """Real API client. Only used when USE_MOCK_SECTORS=false."""

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

    async def screen_companies(self, symbols: list[str]) -> dict[str, Any]:
        result: dict[str, Any] = await self._get(
            "/companies/",
            {
                "where": screener_where(symbols),
                "order_by": "-market_cap",
                "limit": len(symbols),
                "include_query_values": "true",
            },
        )
        return result

    async def get_daily(
        self, symbol: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = await self._get(
            f"/daily/{bare_symbol(symbol)}/", {"start": start, "end": end}
        )
        return result

    async def get_index_daily(
        self, index_code: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = await self._get(
            f"/index-daily/{index_code.lower()}/", {"start": start, "end": end}
        )
        return result

    async def get_subsector_report(self, sub_sector: str) -> dict[str, Any]:
        result: dict[str, Any] = await self._get(
            f"/subsector/report/{sub_sector}/", {"sections": ",".join(SUBSECTOR_SECTIONS)}
        )
        return result

    async def get_top_changes(self, period: str = "1d", n_stock: int = 5) -> dict[str, Any]:
        result: dict[str, Any] = await self._get(
            "/companies/top-changes/",
            {"classifications": "top_gainers,top_losers", "periods": period, "n_stock": n_stock},
        )
        return result

    async def get_most_traded(self, n_stock: int = 5) -> dict[str, Any]:
        result: dict[str, Any] = await self._get("/most-traded/", {"n_stock": n_stock})
        return result

    async def get_news(
        self, symbols: list[str] | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]:
        joined = ",".join(bare_symbol(s) for s in symbols) if symbols else None
        result: dict[str, Any] = await self._get(
            "/news/", {"symbols": joined, "limit": limit, "start": start}
        )
        return result

    async def get_filings(
        self, symbol: str | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]:
        result: dict[str, Any] = await self._get(
            "/filings/",
            {"symbol": bare_symbol(symbol) if symbol else None, "limit": limit, "start": start},
        )
        return result

    async def get_foreign_flow(
        self, symbol: str = "IHSG", start: str | None = None, end: str | None = None
    ) -> dict[str, Any]:
        result: dict[str, Any] = await self._get(
            f"/foreign-flow/{bare_symbol(symbol)}/", {"start": start, "end": end}
        )
        return result
