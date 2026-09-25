"""Market Intelligence endpoint: daily AI-generated analysis insights."""

import asyncio

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.market_intelligence import run_market_intelligence
from app.db.database import get_db
from app.db.insights import insights_generated_today, latest_insights, save_insights
from app.models.schemas import InsightChip, MarketIntelligenceResponse

router = APIRouter()
_gen_lock = asyncio.Lock()


@router.get("/market-intelligence", response_model=MarketIntelligenceResponse)
async def get_market_intelligence(
    db: AsyncSession = Depends(get_db),
) -> MarketIntelligenceResponse:
    if await insights_generated_today(db):
        rows = await latest_insights(db)
        return MarketIntelligenceResponse(
            generated_date=str(rows[0]["generated_date"]),
            insights=[InsightChip(label=r["label"], text=r["content"]) for r in rows],
        )

    async with _gen_lock:
        if await insights_generated_today(db):
            rows = await latest_insights(db)
            return MarketIntelligenceResponse(
                generated_date=str(rows[0]["generated_date"]),
                insights=[
                    InsightChip(label=r["label"], text=r["content"]) for r in rows
                ],
            )

        results = await run_market_intelligence(db)
        await save_insights(db, results)

    rows = await latest_insights(db)
    return MarketIntelligenceResponse(
        generated_date=str(rows[0]["generated_date"]),
        insights=[InsightChip(label=r["label"], text=r["content"]) for r in rows],
    )
