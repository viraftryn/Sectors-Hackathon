from typing import Any

from fastapi import APIRouter

from app.clients.sectors import SectorsClient
from app.config import settings

router = APIRouter()


@router.get("/status")
async def status() -> dict[str, Any]:
    return {
        "status": "ok",
        "service": "invelio-api",
        "version": "0.1.0",
        "mock_data": settings.use_mock_data,
        "sectors_api_calls": SectorsClient.request_count,
    }
