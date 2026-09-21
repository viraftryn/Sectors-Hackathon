from datetime import date, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from app.api.deps import get_sectors
from app.clients.sectors import SectorsSource, bare_symbol
from app.config import settings
from app.models.schemas import (
    Fundamentals,
    PricePoint,
    StockDetail,
    StockListResponse,
    StockSummary,
)

router = APIRouter()

PRICE_HISTORY_DAYS = 90


def pct(value: float | None) -> float | None:
    return None if value is None else round(value * 100, 2)


def ratio(value: float | None) -> float | None:
    return None if value is None else round(value, 2)


def to_summary(row: dict[str, Any]) -> StockSummary:
    q = row["query_values"]
    return StockSummary(
        ticker=bare_symbol(row["symbol"]),
        name=row["company_name"],
        sector=q["sector"],
        sub_sector=q["sub_sector"],
        price=q["last_close_price"],
        change_pct=pct(q.get("daily_close_change")),
        market_cap=q.get("market_cap"),
    )


@router.get("/stocks", response_model=StockListResponse)
async def list_stocks(sectors: SectorsSource = Depends(get_sectors)) -> StockListResponse:
    screener = await sectors.screen_companies(settings.tracked_tickers)
    return StockListResponse(stocks=[to_summary(r) for r in screener["results"]])


@router.get("/stock/{ticker}", response_model=StockDetail)
async def get_stock(ticker: str, sectors: SectorsSource = Depends(get_sectors)) -> StockDetail:
    ticker = bare_symbol(ticker)
    if ticker not in settings.tracked_tickers:
        raise HTTPException(status_code=404, detail=f"{ticker} is not tracked")

    screener = await sectors.screen_companies(settings.tracked_tickers)
    row = next((r for r in screener["results"] if bare_symbol(r["symbol"]) == ticker), None)
    if row is None:
        raise HTTPException(status_code=404, detail=f"No data for {ticker}")

    start = (date.today() - timedelta(days=PRICE_HISTORY_DAYS)).isoformat()
    daily = await sectors.get_daily(ticker, start=start)

    q = row["query_values"]
    return StockDetail(
        **to_summary(row).model_dump(),
        fundamentals=Fundamentals(
            pe=ratio(q.get("pe_ttm")),
            pb=ratio(q.get("pb_mrq")),
            roe_pct=pct(q.get("roe_ttm")),
            der=ratio(q.get("der_mrq")),
            dividend_yield_pct=pct(q.get("yield_ttm")),
        ),
        week52_high=q.get("52_w_high_price"),
        week52_low=q.get("52_w_low_price"),
        prices=[
            PricePoint(
                date=d["date"],
                open=d.get("open"),
                high=d.get("high"),
                low=d.get("low"),
                close=d["close"],
                volume=d.get("volume"),
            )
            for d in daily
        ],
    )
