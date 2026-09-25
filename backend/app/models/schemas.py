import uuid
from datetime import UTC, datetime

from pydantic import BaseModel, Field


def utc_iso(value: datetime) -> str:
    """ISO 8601 in UTC with a Z suffix; naive datetimes are treated as UTC."""
    if value.tzinfo is not None:
        value = value.astimezone(UTC).replace(tzinfo=None)
    return value.isoformat() + "Z"


class StatusResponse(BaseModel):
    status: str
    service: str
    version: str


class StockSummary(BaseModel):
    ticker: str
    name: str
    sector: str
    sub_sector: str
    price: float
    change_pct: float | None
    market_cap: float | None


class StockListResponse(BaseModel):
    stocks: list[StockSummary]


class Fundamentals(BaseModel):
    pe: float | None
    pb: float | None
    roe_pct: float | None
    der: float | None
    dividend_yield_pct: float | None


class PricePoint(BaseModel):
    date: str
    open: float | None
    high: float | None
    low: float | None
    close: float
    volume: int | None


class StockDetail(StockSummary):
    fundamentals: Fundamentals
    week52_high: float | None
    week52_low: float | None
    prices: list[PricePoint]


class IndexPoint(BaseModel):
    date: str
    value: float


class IndexSummary(BaseModel):
    name: str
    value: float
    change_pct: float | None
    date: str
    series: list[IndexPoint]


class Mover(BaseModel):
    ticker: str
    name: str
    price: float
    change_pct: float


class TradedStock(BaseModel):
    ticker: str
    name: str
    volume: int
    price: float


class ForeignFlow(BaseModel):
    date: str
    net_foreign_inflow: float


class MarketOverview(BaseModel):
    ihsg: IndexSummary
    foreign_flow: ForeignFlow | None
    top_gainers: list[Mover]
    top_losers: list[Mover]
    most_traded: list[TradedStock]


# -- Chat -------------------------------------------------------------------


class ChatRequest(BaseModel):
    message: str
    session_id: uuid.UUID = Field(default_factory=uuid.uuid4)


class ChatResponse(BaseModel):
    session_id: uuid.UUID
    response: str


class ScoreBreakdown(BaseModel):
    fundamental: float
    macro: float
    sector: float
    risk: float
    sentiment: float


class Recommendation(BaseModel):
    ticker: str
    name: str
    overall_score: float
    recommendation: str
    reasoning: str
    scores: ScoreBreakdown
    scored_at: str


class RecommendationList(BaseModel):
    scored_at: str | None
    recommendations: list[Recommendation]


class Alert(BaseModel):
    id: int
    ticker: str | None
    alert_type: str
    severity: str
    message: str
    is_read: bool
    created_at: str


class AlertList(BaseModel):
    unread_count: int
    alerts: list[Alert]


class HoldingLotIn(BaseModel):
    id: uuid.UUID | None = None
    ticker: str
    price_per_share: float = Field(gt=0)
    shares: float | None = Field(default=None, gt=0)
    total_invested: float | None = Field(default=None, gt=0)
    buy_date: datetime | None = None


class SellIn(BaseModel):
    ticker: str
    shares: float = Field(gt=0)
    sell_price: float = Field(gt=0)


class SellResult(BaseModel):
    ticker: str
    sold_shares: float
    realized_pnl: float
    remaining_shares: float


class HoldingLot(BaseModel):
    id: str
    ticker: str
    stock_name: str | None
    shares: float
    price_per_share: float
    total_invested: float
    buy_date: str


class HoldingLotList(BaseModel):
    lots: list[HoldingLot]


class Position(BaseModel):
    ticker: str
    name: str
    shares: float
    avg_buy_price: float
    total_cost: float
    current_price: float
    current_value: float
    pnl: float
    pnl_pct: float


class PortfolioSummary(BaseModel):
    total_cost: float
    current_value: float
    pnl: float
    pnl_pct: float
    positions: list[Position]


# -- Market Intelligence -----------------------------------------------------


class InsightChip(BaseModel):
    label: str
    text: str


class MarketIntelligenceResponse(BaseModel):
    generated_date: str
    insights: list[InsightChip]
