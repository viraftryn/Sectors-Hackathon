from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import alerts, cache, chat, health, market, portfolio, scoring, stocks
from app.clients.sectors import SectorsError
from app.config import settings

app = FastAPI(
    title="Invelio API",
    description="Agentic AI backend for Indonesian stock analysis",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(cache.router, prefix="/api", tags=["cache"])
app.include_router(stocks.router, prefix="/api", tags=["stocks"])
app.include_router(market.router, prefix="/api", tags=["market"])
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(scoring.router, prefix="/api", tags=["scoring"])
app.include_router(alerts.router, prefix="/api", tags=["alerts"])
app.include_router(portfolio.router, prefix="/api", tags=["portfolio"])


@app.exception_handler(SectorsError)
async def sectors_error_handler(request: Request, exc: SectorsError) -> JSONResponse:
    return JSONResponse(
        status_code=502,
        content={"detail": "Market data unavailable", "upstream_status": exc.status_code},
    )
