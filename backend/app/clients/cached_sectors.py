"""Cached wrapper around SectorsClient — every call checks cache before hitting the API."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import cache_get, cache_set
from app.clients.sectors import SectorsClient, bare_symbol
from app.config import settings


class CachedSectorsClient:
    """Drop-in replacement for SectorsClient that adds two-layer caching.

    Usage:
        client = CachedSectorsClient(db_session)
        data = await client.get_daily("BBCA")
    """

    def __init__(self, db: AsyncSession) -> None:
        self._raw = SectorsClient()
        self._db = db

    async def _cached(self, key: str, ttl: int, fetcher: Callable[[], Awaitable[Any]]) -> Any:
        hit = await cache_get(key, self._db)
        if hit is not None:
            return hit
        data = await fetcher()
        await cache_set(key, data, ttl, self._db)
        return data

    # --- Screener: fundamentals + latest price for tracked tickers (5min) ---

    async def screen_companies(self, symbols: list[str]) -> dict[str, Any]:
        key = "screener:" + ",".join(sorted(bare_symbol(s) for s in symbols))
        result: dict[str, Any] = await self._cached(
            key, settings.cache_ttl_prices, lambda: self._raw.screen_companies(symbols)
        )
        return result

    # --- Price / Trending data (5min) ---

    async def get_daily(
        self, symbol: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = await self._cached(
            f"daily:{bare_symbol(symbol)}:{start}:{end}",
            settings.cache_ttl_prices,
            lambda: self._raw.get_daily(symbol, start, end),
        )
        return result

    async def get_top_changes(self, period: str = "1d", n_stock: int = 5) -> dict[str, Any]:
        result: dict[str, Any] = await self._cached(
            f"top_changes:{period}:{n_stock}",
            settings.cache_ttl_prices,
            lambda: self._raw.get_top_changes(period, n_stock),
        )
        return result

    async def get_most_traded(self, n_stock: int = 5) -> dict[str, Any]:
        result: dict[str, Any] = await self._cached(
            f"most_traded:{n_stock}",
            settings.cache_ttl_prices,
            lambda: self._raw.get_most_traded(n_stock),
        )
        return result

    # --- Market index (10min) ---

    async def get_index_daily(
        self, index_code: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = await self._cached(
            f"index_daily:{index_code.lower()}:{start}:{end}",
            settings.cache_ttl_market_index,
            lambda: self._raw.get_index_daily(index_code, start, end),
        )
        return result

    # --- Sector reports, filings, foreign flow (1h) ---

    async def get_subsector_report(self, sub_sector: str) -> dict[str, Any]:
        result: dict[str, Any] = await self._cached(
            f"subsector_report:{sub_sector}",
            settings.cache_ttl_sector_reports,
            lambda: self._raw.get_subsector_report(sub_sector),
        )
        return result

    async def get_filings(
        self, symbol: str | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]:
        result: dict[str, Any] = await self._cached(
            f"filings:{symbol or 'all'}:{limit}:{start}",
            settings.cache_ttl_sector_reports,
            lambda: self._raw.get_filings(symbol, limit, start),
        )
        return result

    async def get_foreign_flow(
        self, symbol: str = "IHSG", start: str | None = None, end: str | None = None
    ) -> dict[str, Any]:
        result: dict[str, Any] = await self._cached(
            f"foreign_flow:{bare_symbol(symbol)}:{start}:{end}",
            settings.cache_ttl_sector_reports,
            lambda: self._raw.get_foreign_flow(symbol, start, end),
        )
        return result

    # --- News (15min) ---

    async def get_news(
        self, symbols: list[str] | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]:
        tickers = ",".join(sorted(bare_symbol(s) for s in symbols)) if symbols else "all"
        result: dict[str, Any] = await self._cached(
            f"news:{tickers}:{limit}:{start}",
            settings.cache_ttl_news,
            lambda: self._raw.get_news(symbols, limit, start),
        )
        return result
