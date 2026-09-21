from datetime import date, timedelta
from typing import Any

from fastapi import APIRouter, Depends

from app.api.deps import get_sectors
from app.api.routes.stocks import pct
from app.clients.sectors import SectorsSource, bare_symbol
from app.models.schemas import (
    ForeignFlow,
    IndexPoint,
    IndexSummary,
    MarketOverview,
    Mover,
    TradedStock,
)

router = APIRouter()


@router.get("/market-overview", response_model=MarketOverview)
async def market_overview(sectors: SectorsSource = Depends(get_sectors)) -> MarketOverview:
    ihsg = await sectors.get_index_daily("ihsg")
    movers = await sectors.get_top_changes("1d")
    traded = await sectors.get_most_traded()
    week_ago = (date.today() - timedelta(days=7)).isoformat()
    flow = await sectors.get_foreign_flow("IHSG", start=week_ago)

    last = ihsg[-1]
    change = last["price"] / ihsg[-2]["price"] - 1 if len(ihsg) > 1 else None
    latest_traded = traded[max(traded)] if traded else []
    latest_flow = flow["data"][-1] if flow["data"] else None

    def to_movers(rows: list[dict[str, Any]]) -> list[Mover]:
        return [
            Mover(
                ticker=bare_symbol(r["symbol"]),
                name=r["name"],
                price=r["last_close_price"],
                change_pct=round(r["price_change"] * 100, 2),
            )
            for r in rows
        ]

    return MarketOverview(
        ihsg=IndexSummary(
            name="IHSG",
            value=last["price"],
            change_pct=pct(change),
            date=last["date"],
            series=[IndexPoint(date=p["date"], value=p["price"]) for p in ihsg],
        ),
        foreign_flow=ForeignFlow(
            date=latest_flow["date"], net_foreign_inflow=latest_flow["net_foreign_inflow"]
        )
        if latest_flow
        else None,
        top_gainers=to_movers(movers["top_gainers"].get("1d", [])),
        top_losers=to_movers(movers["top_losers"].get("1d", [])),
        most_traded=[
            TradedStock(
                ticker=bare_symbol(t["symbol"]),
                name=t["company_name"],
                volume=t["volume"],
                price=t["price"],
            )
            for t in latest_traded
        ],
    )
