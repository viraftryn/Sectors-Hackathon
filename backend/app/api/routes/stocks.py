from typing import Any, cast

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_sectors
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import bare_symbol
from app.db.database import get_db
from app.models.schemas import (
    Fundamentals,
    PricePoint,
    StockDetail,
    StockListResponse,
    StockSummary,
)

router = APIRouter()


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


async def tracked_rows(sectors: CachedSectorsClient) -> list[dict[str, Any]]:
    screener = cast(dict[str, Any], await sectors.list_companies())
    return cast(list[dict[str, Any]], screener["results"])


@router.get("/stocks", response_model=StockListResponse)
async def list_stocks(sectors: CachedSectorsClient = Depends(get_sectors)) -> StockListResponse:
    return StockListResponse(stocks=[to_summary(r) for r in await tracked_rows(sectors)])


@router.get("/stock/{ticker}", response_model=StockDetail)
async def get_stock(
    ticker: str,
    db: AsyncSession = Depends(get_db),
    sectors: CachedSectorsClient = Depends(get_sectors),
) -> StockDetail:
    ticker = bare_symbol(ticker)
    rows = await tracked_rows(sectors)
    row = next((r for r in rows if bare_symbol(r["symbol"]) == ticker), None)
    if row is None:
        raise HTTPException(status_code=404, detail=f"{ticker} is not tracked")

    # Priority 1: Check PostgreSQL `stock_daily_prices` table in database
    db_prices = await db.execute(
        text(
            "SELECT date, open, high, low, close, volume FROM stock_daily_prices "
            "WHERE ticker = :t ORDER BY date ASC"
        ),
        {"t": ticker},
    )
    db_rows = db_prices.mappings().all()
    if db_rows:
        daily = [
            {
                "date": str(r["date"]),
                "open": float(r["open"]) if r["open"] is not None else None,
                "high": float(r["high"]) if r["high"] is not None else None,
                "low": float(r["low"]) if r["low"] is not None else None,
                "close": float(r["close"]),
                "volume": int(r["volume"]) if r["volume"] is not None else None,
            }
            for r in db_rows
        ]
    else:
        daily = cast(list[dict[str, Any]], await sectors.get_daily_prices(ticker))

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
