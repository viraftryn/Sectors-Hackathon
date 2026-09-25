"""Sync 365-day (1 Year) daily price history from Sectors API v2 to Supabase PostgreSQL."""

import asyncio
import logging
from datetime import date, timedelta
from typing import Any
import httpx
from sqlalchemy import text

# Import from backend & load backend/.env
import sys
import os
from pathlib import Path
from dotenv import load_dotenv

backend_dir = Path(__file__).resolve().parent.parent / "backend"
load_dotenv(backend_dir / ".env")
sys.path.insert(0, str(backend_dir))

from app.db.database import get_engine
from app.clients.sectors import bare_symbol
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

env_key = os.getenv("SECTORS_API_KEY", "")
if env_key == "your_sectors_api_key_here":
    env_key = ""

SECTORS_API_KEY = (sys.argv[2] if len(sys.argv) > 2 else "") or env_key

UPSERT_PRICE_SQL = """
INSERT INTO stock_daily_prices (ticker, date, open, high, low, close, volume)
VALUES (:ticker, :date, :open, :high, :low, :close, :volume)
ON CONFLICT (ticker, date) DO UPDATE SET
    open = EXCLUDED.open,
    high = EXCLUDED.high,
    low = EXCLUDED.low,
    close = EXCLUDED.close,
    volume = EXCLUDED.volume;
"""


def generate_365d_windows() -> list[tuple[str, str]]:
    """Generate 4 consecutive quarterly windows covering 365 days."""
    today = date(2026, 9, 25)
    windows = []
    
    current_end = today
    for _ in range(4):
        start = current_end - timedelta(days=91)
        windows.append((start.strftime("%Y-%m-%d"), current_end.strftime("%Y-%m-%d")))
        current_end = start - timedelta(days=1)
        
    return list(reversed(windows))


async def sync_ticker_365d(ticker: str) -> int:
    ticker = bare_symbol(ticker)
    headers = {"Authorization": SECTORS_API_KEY}
    windows = generate_365d_windows()
    
    logger.info("Fetching 365-day history for %s across windows: %s", ticker, windows)
    
    all_points: dict[str, dict[str, Any]] = {}
    async with httpx.AsyncClient() as client:
        for s, e in windows:
            url = f"https://api.sectors.app/v2/daily/{ticker}/?start={s}&end={e}"
            try:
                res = await client.get(url, headers=headers, timeout=20.0)
                if res.status_code == 200:
                    items = res.json()
                    if isinstance(items, list):
                        for it in items:
                            all_points[it["date"]] = it
                else:
                    logger.warning("Failed window %s -> %s for %s (HTTP %d)", s, e, ticker, res.status_code)
            except Exception as exc:
                logger.error("Error fetching window %s -> %s for %s: %s", s, e, ticker, exc)
            await asyncio.sleep(0.3)

    if not all_points:
        logger.warning("No data points fetched for %s", ticker)
        return 0

    sorted_dates = sorted(all_points.keys())
    logger.info("Fetched %d unique trading days for %s (%s -> %s)", len(all_points), ticker, sorted_dates[0], sorted_dates[-1])

    engine = get_engine()
    async with engine.begin() as conn:
        for d in sorted_dates:
            p = all_points[d]
            dt_obj = date.fromisoformat(p["date"])
            await conn.execute(
                text(UPSERT_PRICE_SQL),
                {
                    "ticker": ticker,
                    "date": dt_obj,
                    "open": p.get("open"),
                    "high": p.get("high"),
                    "low": p.get("low"),
                    "close": p["close"],
                    "volume": p.get("volume"),
                },
            )

    logger.info("Successfully stored %d days into stock_daily_prices for %s", len(sorted_dates), ticker)
    return len(sorted_dates)


async def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "BBCA"
    print(f"\n========================================================")
    print(f" SINKRONISASI 365 HARI (1 TAHUN) HARGA HISTORIS: {target}")
    print(f"========================================================\n")
    
    count = await sync_ticker_365d(target)
    
    # Query check
    engine = get_engine()
    async with engine.connect() as conn:
        res = await conn.execute(
            text("SELECT MIN(date), MAX(date), COUNT(*) FROM stock_daily_prices WHERE ticker = :t"),
            {"t": bare_symbol(target)}
        )
        row = res.fetchone()
        print(f"\n=== HASIL VERIFIKASI SUPABASE (stock_daily_prices) ===")
        print(f"Ticker:         {target}")
        print(f"Total Baris:    {row[2]} hari bursa")
        print(f"Rentang Waktu:  {row[0]} s/d {row[1]}")


if __name__ == "__main__":
    asyncio.run(main())
