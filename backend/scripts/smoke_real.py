"""Check the backend against the real Sectors API, one stage at a time.

Every stage spends credits, so each one is opt-in and prints what it used:

    python scripts/smoke_real.py stocks     # ~1 credit
    python scripts/smoke_real.py market     # ~6 credits
    python scripts/smoke_real.py scoring    # ~47 credits, writes to the database

Needs SECTORS_API_KEY, a reachable DATABASE_URL and (for scoring) GEMINI_API_KEY in .env.
Cached responses are reused, so re-running a stage within its TTL costs nothing.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text

from app.agents.scoring import run_scoring
from app.cache import cache_stats
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import SectorsClient
from app.config import settings
from app.db.database import get_session_factory
from app.db.scores import save_scores

STAGES = ("stocks", "market", "scoring")


async def check_database() -> None:
    async with get_session_factory()() as db:
        await db.execute(text("SELECT 1"))
    print(f"database ok: {settings.database_url.split('@')[-1]}")


async def stage_stocks(sectors: CachedSectorsClient) -> None:
    rows = cast(dict[str, Any], await sectors.list_companies())["results"]
    print(f"screener returned {len(rows)} companies")
    for row in rows[:3]:
        q = row["query_values"]
        print(
            f"  {row['symbol']:10} {q['last_close_price']:>8}  PE {q['pe_ttm']}  ROE {q['roe_ttm']}"
        )


async def stage_market(sectors: CachedSectorsClient) -> None:
    ihsg = cast(list[dict[str, Any]], await sectors.get_ihsg())
    movers = cast(dict[str, Any], await sectors.get_top_companies())
    traded = cast(dict[str, Any], await sectors.get_most_traded())
    flow = cast(dict[str, Any], await sectors.get_foreign_flow("IHSG"))
    print(f"ihsg last: {ihsg[-1]}")
    print(f"top gainers 1d: {[m['symbol'] for m in movers['top_gainers']['1d']]}")
    print(f"most traded days: {len(traded)}")
    print(f"foreign flow last: {flow['data'][-1]}")


async def stage_scoring(sectors: CachedSectorsClient, db: Any) -> None:
    results = await run_scoring(sectors)
    scored_at = await save_scores(db, results)
    print(f"saved {len(results)} scores at {scored_at.isoformat()}")
    for r in results:
        line = f"  {r['ticker']:6} {r['overall_score']:>5}  {r['recommendation']:5}"
        print(line, r["reasoning"][:80])


async def main(stage: str) -> None:
    if settings.use_mock_data:
        raise SystemExit("USE_MOCK_DATA is true — set it to false in .env to check real data")
    before = SectorsClient.request_count
    await check_database()

    async with get_session_factory()() as db:
        sectors = CachedSectorsClient(db)
        if stage == "stocks":
            await stage_stocks(sectors)
        elif stage == "market":
            await stage_market(sectors)
        else:
            await stage_scoring(sectors, db)

    stats = cache_stats()
    print(
        f"\nSectors requests this run: {SectorsClient.request_count - before} "
        f"(cache hits {stats['hits']}, misses {stats['misses']})"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=STAGES)
    asyncio.run(main(parser.parse_args().stage))
