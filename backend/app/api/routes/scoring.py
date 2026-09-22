from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.scoring import run_scoring
from app.api.deps import get_sectors
from app.cache import _utcnow
from app.clients.cached_sectors import CachedSectorsClient
from app.config import settings
from app.db.database import get_db
from app.db.scores import last_scored_at, latest_scores, save_scores
from app.models.schemas import Recommendation, RecommendationList, ScoreBreakdown

router = APIRouter()


def to_recommendation(row: dict[str, Any]) -> Recommendation:
    return Recommendation(
        ticker=row["ticker"],
        name=row["name"],
        overall_score=row["overall_score"],
        recommendation=row["recommendation"],
        reasoning=row["reasoning"],
        scores=ScoreBreakdown(
            fundamental=row["fundamental_score"],
            macro=row["macro_score"],
            sector=row["sector_score"],
            risk=row["risk_score"],
            sentiment=row["sentiment_score"],
        ),
        scored_at=row["scored_at"].isoformat() + "Z",
    )


async def recommendation_list(db: AsyncSession) -> RecommendationList:
    rows = await latest_scores(db)
    items = [to_recommendation(r) for r in rows]
    return RecommendationList(
        scored_at=max((i.scored_at for i in items), default=None), recommendations=items
    )


@router.get("/recommendations", response_model=RecommendationList)
async def get_recommendations(db: AsyncSession = Depends(get_db)) -> RecommendationList:
    return await recommendation_list(db)


@router.post("/scoring/run", response_model=RecommendationList)
async def trigger_scoring(
    db: AsyncSession = Depends(get_db), sectors: CachedSectorsClient = Depends(get_sectors)
) -> RecommendationList:
    last = await last_scored_at(db)
    fresh = last and (_utcnow() - last).total_seconds() < settings.scoring_min_interval_seconds
    if not fresh:
        await save_scores(db, await run_scoring(sectors))
    return await recommendation_list(db)
