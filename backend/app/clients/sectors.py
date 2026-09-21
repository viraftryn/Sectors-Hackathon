from typing import Any

import httpx

from app.config import settings


class SectorsClient:
    """Wrapper for the Sectors REST API with auth."""

    def __init__(self) -> None:
        self._base_url = settings.sectors_base_url
        self._headers = {"Authorization": settings.sectors_api_key}

    async def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self._base_url}{path}",
                headers=self._headers,
                params=params,
                timeout=30.0,
            )
            response.raise_for_status()
            return response.json()

    # --- Fundamental / Company data (cache: 24h) ---

    async def get_company_report(self, ticker: str) -> Any:
        return await self._get(f"/companies/report/{ticker}/")

    async def list_companies(self) -> Any:
        return await self._get("/companies/")

    # --- Price / Trending data (cache: 5min) ---

    async def get_daily_prices(self, ticker: str) -> Any:
        return await self._get(f"/daily/{ticker}/")

    async def get_most_traded(self) -> Any:
        return await self._get("/most-traded/")

    async def get_top_companies(self) -> Any:
        return await self._get("/top-companies/")

    # --- Market index (cache: 10min) ---

    async def get_idx_total(self) -> Any:
        return await self._get("/idx-total/")

    # --- Sector reports (cache: 1h) ---

    async def get_sector_report(self) -> Any:
        return await self._get("/sector/report/")

    # --- News / Sentiment (cache: 15min / 1h) ---

    async def get_news(self, ticker: str | None = None) -> Any:
        params = {"ticker": ticker} if ticker else None
        return await self._get("/news/", params=params)

    async def get_news_filings(self, ticker: str | None = None) -> Any:
        params = {"ticker": ticker} if ticker else None
        return await self._get("/news/filings/", params=params)
