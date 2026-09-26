"""CLI / Cron script to generate daily AI stock insights for all tracked tickers.

Usage:
    python -m scripts.generate_stock_insights [--force] [--ticker BBCA]
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys

from app.agents.stock_insights import (
    generate_all_stock_insights,
    generate_stock_insights_for_ticker,
)
from app.db.database import get_session_factory

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("generate_stock_insights")


async def main() -> None:
    parser = argparse.ArgumentParser(description="Generate daily AI stock insights")
    parser.add_argument("--force", action="store_true", help="Force regenerate even if already generated today")
    parser.add_argument("--ticker", type=str, default=None, help="Generate for a specific ticker only (e.g. BBCA)")
    args = parser.parse_args()

    factory = get_session_factory()
    async with factory() as db:
        if args.ticker:
            ticker = args.ticker.upper()
            logger.info("Generating AI insights for %s (force=%s)...", ticker, args.force)
            insights = await generate_stock_insights_for_ticker(db, ticker, force_refresh=args.force)
            logger.info("Generated %d insights for %s:", len(insights), ticker)
            for item in insights:
                logger.info("[%s] %s", item["label"], item["content"][:100] + "...")
        else:
            logger.info("Starting batch generation for all tracked tickers (force=%s)...", args.force)
            results = await generate_all_stock_insights(db, force_refresh=args.force)
            logger.info("Completed batch generation for %d tickers.", len(results))


if __name__ == "__main__":
    asyncio.run(main())
