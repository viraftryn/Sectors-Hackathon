import httpx

from app.config import settings


class SectorsClient:
    """Wrapper for the Sectors REST API with auth and rate limiting."""

    def __init__(self) -> None:
        self._base_url = settings.sectors_base_url
        self._headers = {"Authorization": settings.sectors_api_key}

    async def _get(self, path: str, params: dict | None = None) -> dict:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self._base_url}{path}",
                headers=self._headers,
                params=params,
                timeout=30.0,
            )
            response.raise_for_status()
            return response.json()

    async def get_company_report(self, ticker: str) -> dict:
        return await self._get(f"/companies/report/{ticker}/")

    async def get_daily_prices(self, ticker: str) -> dict:
        return await self._get(f"/daily/{ticker}/")

    async def list_companies(self) -> dict:
        return await self._get("/companies/")

    async def get_sector_report(self) -> dict:
        return await self._get("/sector/report/")

    async def get_most_traded(self) -> dict:
        return await self._get("/most-traded/")

    async def get_top_companies(self) -> dict:
        return await self._get("/top-companies/")

    async def get_idx_total(self) -> dict:
        return await self._get("/idx-total/")
