"""Cached wrapper around SectorsClient — every call checks cache before hitting the API."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import cast

from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import cache_get, cache_set
from app.clients.sectors import SectorsClient
from app.config import settings
from app.mock_data.fixtures import JsonData, get_mock_response


class CachedSectorsClient:
    """Drop-in replacement for SectorsClient that adds two-layer caching.

    Lookup order on every call: L1 memory -> L2 PostgreSQL -> source. The source is the
    real Sectors API, or (when settings.use_mock_data is on) a saved fixture — so the whole
    team can build against realistic data for zero credits.

    Usage:
        client = CachedSectorsClient(db_session)
        data = await client.get_daily_prices("BBCA")
    """

    def __init__(self, db: AsyncSession) -> None:
        self._raw = SectorsClient()
        self._db = db

    async def _cached(
        self, key: str, ttl: int, fetcher: Callable[[], Awaitable[JsonData]]
    ) -> JsonData:
        hit = await cache_get(key, self._db)
        if hit is not None:
            return cast(JsonData, hit)
        data: JsonData = get_mock_response(key) if settings.use_mock_data else await fetcher()
        await cache_set(key, data, ttl, self._db)
        return data

    # --- Fundamental / Company data (24h) ---

    async def get_company_report(self, ticker: str) -> JsonData:
        return await self._cached(
            f"company_report:{ticker}",
            settings.cache_ttl_fundamentals,
            lambda: self._raw.get_company_report(ticker),
        )

    async def list_companies(self) -> JsonData:
        return await self._cached(
            "companies_list",
            settings.cache_ttl_fundamentals,
            self._raw.list_companies,
        )

    # --- Price / Trending data (5min) ---

    async def get_daily_prices(self, ticker: str) -> JsonData:
        return await self._cached(
            f"daily_prices:{ticker}",
            settings.cache_ttl_prices,
            lambda: self._raw.get_daily_prices(ticker),
        )

    async def get_most_traded(self) -> JsonData:
        return await self._cached(
            "most_traded",
            settings.cache_ttl_prices,
            self._raw.get_most_traded,
        )

    async def get_top_companies(self) -> JsonData:
        return await self._cached(
            "top_companies",
            settings.cache_ttl_prices,
            self._raw.get_top_companies,
        )

    # --- Market index (10min) ---

    async def get_idx_total(self) -> JsonData:
        return await self._cached(
            "idx_total",
            settings.cache_ttl_market_index,
            self._raw.get_idx_total,
        )

    # --- Sector reports (1h) ---

    async def get_sector_report(self) -> JsonData:
        return await self._cached(
            "sector_report",
            settings.cache_ttl_sector_reports,
            self._raw.get_sector_report,
        )

    # --- News (15min) / Filings (1h) ---

    async def get_news(self, ticker: str | None = None) -> JsonData:
        key = f"news:{ticker}" if ticker else "news:all"
        return await self._cached(
            key,
            settings.cache_ttl_news,
            lambda: self._raw.get_news(ticker),
        )

    async def get_news_filings(self, ticker: str | None = None) -> JsonData:
        key = f"news_filings:{ticker}" if ticker else "news_filings:all"
        return await self._cached(
            key,
            settings.cache_ttl_sector_reports,
            lambda: self._raw.get_news_filings(ticker),
        )
