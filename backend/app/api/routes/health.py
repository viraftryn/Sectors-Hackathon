from fastapi import APIRouter

router = APIRouter()


@router.get("/status")
async def status() -> dict[str, str]:
    return {"status": "ok", "service": "invelio-api", "version": "0.1.0"}
