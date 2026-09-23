import uuid
from collections import defaultdict
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_sectors
from app.api.routes.stocks import tracked_rows
from app.cache import _coerce_dt
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import bare_symbol
from app.config import settings
from app.db.database import get_db
from app.models.schemas import (
    HoldingLot,
    HoldingLotIn,
    HoldingLotList,
    PortfolioSummary,
    Position,
    utc_iso,
)

router = APIRouter()

LOT_COLUMNS = "id, ticker, stock_name, shares, price_per_share, total_invested, buy_date"


def device_id(x_device_id: str | None = Header(default=None)) -> str:
    if not x_device_id or len(x_device_id) > 64:
        raise HTTPException(status_code=400, detail="X-Device-Id header is required")
    return x_device_id


def to_lot(row: Any) -> HoldingLot:
    return HoldingLot(
        id=str(row.id),
        ticker=row.ticker,
        stock_name=row.stock_name,
        shares=float(row.shares),
        price_per_share=float(row.price_per_share),
        total_invested=float(row.total_invested),
        buy_date=utc_iso(_coerce_dt(row.buy_date)),
    )


async def fetch_lots(db: AsyncSession, device: str) -> list[Any]:
    rows = await db.execute(
        text(
            f"SELECT {LOT_COLUMNS} FROM user_holdings WHERE device_id = :device "
            "ORDER BY buy_date DESC"
        ),
        {"device": device},
    )
    return list(rows)


@router.get("/portfolio/lots", response_model=HoldingLotList)
async def list_lots(
    device: str = Depends(device_id), db: AsyncSession = Depends(get_db)
) -> HoldingLotList:
    return HoldingLotList(lots=[to_lot(r) for r in await fetch_lots(db, device)])


@router.post("/portfolio/lots", response_model=HoldingLot, status_code=201)
async def add_lot(
    lot: HoldingLotIn, device: str = Depends(device_id), db: AsyncSession = Depends(get_db)
) -> HoldingLot:
    ticker = bare_symbol(lot.ticker)
    if ticker not in settings.tracked_tickers:
        raise HTTPException(status_code=422, detail=f"{ticker} is not tracked")
    if lot.shares is not None:
        shares = lot.shares
    elif lot.total_invested is not None:
        shares = lot.total_invested / lot.price_per_share
    else:
        raise HTTPException(status_code=422, detail="Provide shares or total_invested")
    total = lot.total_invested or shares * lot.price_per_share
    buy_date = lot.buy_date or datetime.now(UTC)
    if buy_date.tzinfo is None:
        buy_date = buy_date.replace(tzinfo=UTC)
    now = datetime.now(UTC)

    await db.execute(
        text(
            "INSERT INTO user_installations (device_id, created_at, last_active_at) "
            "VALUES (:device, :now, :now) "
            "ON CONFLICT (device_id) DO UPDATE SET last_active_at = :now"
        ),
        {"device": device, "now": now},
    )
    name = (
        await db.execute(text("SELECT name FROM stocks WHERE ticker = :t"), {"t": ticker})
    ).scalar()
    lot_id = str(lot.id or uuid.uuid4())
    await db.execute(
        text(
            "INSERT INTO user_holdings (id, device_id, ticker, stock_name, shares, "
            "price_per_share, total_invested, buy_date, created_at, updated_at) "
            "VALUES (:id, :device, :ticker, :name, :shares, :price, :total, :buy_date, :now, :now)"
        ),
        {
            "id": lot_id,
            "device": device,
            "ticker": ticker,
            "name": name,
            "shares": shares,
            "price": lot.price_per_share,
            "total": total,
            "buy_date": buy_date,
            "now": now,
        },
    )
    await db.commit()
    return HoldingLot(
        id=lot_id,
        ticker=ticker,
        stock_name=name,
        shares=shares,
        price_per_share=lot.price_per_share,
        total_invested=total,
        buy_date=utc_iso(buy_date),
    )


@router.delete("/portfolio/lots/{lot_id}", status_code=204)
async def delete_lot(
    lot_id: uuid.UUID, device: str = Depends(device_id), db: AsyncSession = Depends(get_db)
) -> Response:
    result = await db.execute(
        text("DELETE FROM user_holdings WHERE id = :id AND device_id = :device"),
        {"id": str(lot_id), "device": device},
    )
    await db.commit()
    if not getattr(result, "rowcount", 0):
        raise HTTPException(status_code=404, detail="Lot not found")
    return Response(status_code=204)


@router.get("/portfolio", response_model=PortfolioSummary)
async def portfolio_summary(
    device: str = Depends(device_id),
    db: AsyncSession = Depends(get_db),
    sectors: CachedSectorsClient = Depends(get_sectors),
) -> PortfolioSummary:
    lots = await fetch_lots(db, device)
    quotes = {bare_symbol(r["symbol"]): r for r in await tracked_rows(sectors)}

    grouped: dict[str, list[Any]] = defaultdict(list)
    for lot in lots:
        grouped[lot.ticker].append(lot)

    positions = []
    for ticker, ticker_lots in grouped.items():
        shares = sum(float(lot.shares) for lot in ticker_lots)
        cost = sum(float(lot.total_invested) for lot in ticker_lots)
        quote = quotes.get(ticker)
        price = float(quote["query_values"]["last_close_price"]) if quote else cost / shares
        value = shares * price
        positions.append(
            Position(
                ticker=ticker,
                name=quote["company_name"] if quote else ticker_lots[0].stock_name or ticker,
                shares=round(shares, 4),
                avg_buy_price=round(cost / shares, 2),
                total_cost=round(cost, 2),
                current_price=price,
                current_value=round(value, 2),
                pnl=round(value - cost, 2),
                pnl_pct=round((value / cost - 1) * 100, 2),
            )
        )
    positions.sort(key=lambda p: p.current_value, reverse=True)

    total_cost = sum(p.total_cost for p in positions)
    total_value = sum(p.current_value for p in positions)
    return PortfolioSummary(
        total_cost=round(total_cost, 2),
        current_value=round(total_value, 2),
        pnl=round(total_value - total_cost, 2),
        pnl_pct=round((total_value / total_cost - 1) * 100, 2) if total_cost else 0.0,
        positions=positions,
    )
