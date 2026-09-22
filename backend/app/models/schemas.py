from pydantic import BaseModel


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
