"""Sync stock news and filings from Sectors API into Supabase PostgreSQL."""

import asyncio
import json
import logging
from datetime import datetime
from typing import Any

from sqlalchemy import text
from app.db.database import get_engine
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import bare_symbol

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DDL_STATEMENTS = [
    """
    CREATE TABLE IF NOT EXISTS stock_news (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        title TEXT NOT NULL,
        body TEXT,
        source_url TEXT,
        thumbnail_url TEXT,
        publisher VARCHAR(100),
        published_at TIMESTAMPTZ NOT NULL,
        tickers TEXT[] NOT NULL DEFAULT '{}',
        sector VARCHAR(100),
        sentiment VARCHAR(20),
        tags TEXT[] NOT NULL DEFAULT '{}',
        is_filing BOOLEAN NOT NULL DEFAULT FALSE,
        raw_payload JSONB,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    """,
    "CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_news_source_title ON stock_news (COALESCE(source_url, ''), title);",
    "CREATE INDEX IF NOT EXISTS idx_stock_news_published ON stock_news (published_at DESC);",
    "CREATE INDEX IF NOT EXISTS idx_stock_news_tickers ON stock_news USING GIN (tickers);",
]

UPSERT_NEWS_SQL = """
INSERT INTO stock_news (
    title, body, source_url, thumbnail_url, publisher,
    published_at, tickers, sector, sentiment, tags, is_filing, raw_payload
) VALUES (
    :title, :body, :source_url, :thumbnail_url, :publisher,
    :published_at, :tickers, :sector, :sentiment, :tags, :is_filing, :raw_payload
)
ON CONFLICT (COALESCE(source_url, ''), title) DO UPDATE SET
    body = EXCLUDED.body,
    thumbnail_url = EXCLUDED.thumbnail_url,
    sentiment = EXCLUDED.sentiment,
    tags = EXCLUDED.tags,
    tickers = EXCLUDED.tickers,
    raw_payload = EXCLUDED.raw_payload;
"""


def _detect_sentiment(tags: list[str]) -> str:
    tags_lower = [t.lower() for t in tags]
    if "bullish" in tags_lower:
        return "Bullish"
    elif "bearish" in tags_lower:
        return "Bearish"
    return "Neutral"


def _clean_tickers(symbols: list[str] | str | None, default_ticker: str) -> list[str]:
    res = []
    if isinstance(symbols, list):
        for s in symbols:
            clean = bare_symbol(s)
            if clean and clean not in res:
                res.append(clean)
    elif isinstance(symbols, str):
        clean = bare_symbol(symbols)
        if clean:
            res.append(clean)
    if not res and default_ticker:
        res.append(bare_symbol(default_ticker))
    return res


async def sync_ticker_news(ticker: str):
    engine = get_engine()
    client = CachedSectorsClient(db=None)

    # 1. Pastikan tabel terbuat di Supabase & bersihkan mock data lama
    async with engine.begin() as conn:
        for stmt in DDL_STATEMENTS:
            await conn.execute(text(stmt))
        del_res = await conn.execute(text("DELETE FROM stock_news WHERE :ticker = ANY(tickers);"), {"ticker": bare_symbol(ticker)})
        logger.info("Cleared %s previous records for %s", del_res.rowcount, ticker)
    logger.info("Table stock_news verified/created.")

    # 2. Fetch General News from Sectors API Live
    logger.info("Fetching LIVE news for %s from Sectors API...", ticker)
    news_res = await client.get_news(ticker)
    news_items = news_res.get("results", []) if isinstance(news_res, dict) else (news_res if isinstance(news_res, list) else [])
    logger.info("Received %d live news items from Sectors API", len(news_items))

    # 3. Fetch IDX Filings from Sectors API Live
    logger.info("Fetching LIVE IDX filings for %s from Sectors API...", ticker)
    filings_res = await client.get_news_filings(ticker)
    filing_items = filings_res.get("results", []) if isinstance(filings_res, dict) else (filings_res if isinstance(filings_res, list) else [])
    logger.info("Received %d live filing items from Sectors API", len(filing_items))

    total_inserted = 0

    async with engine.begin() as conn:
        # Insert news
        for item in news_items:
            tags = item.get("tags") or []
            sentiment = _detect_sentiment(tags)
            symbols = item.get("symbols") or [item.get("symbol")]
            tickers = _clean_tickers(symbols, ticker)

            ts_raw = item.get("timestamp") or datetime.utcnow().isoformat()
            try:
                published_at = datetime.fromisoformat(ts_raw)
            except Exception:
                published_at = datetime.utcnow()

            params = {
                "title": item.get("title", "Untitled News"),
                "body": item.get("body", ""),
                "source_url": item.get("source") or item.get("url"),
                "thumbnail_url": item.get("thumbnail"),
                "publisher": item.get("publisher", "Sectors"),
                "published_at": published_at,
                "tickers": tickers,
                "sector": item.get("sector"),
                "sentiment": sentiment,
                "tags": tags,
                "is_filing": False,
                "raw_payload": json.dumps(item),
            }
            await conn.execute(text(UPSERT_NEWS_SQL), params)
            total_inserted += 1

        # Insert filings
        for item in filing_items:
            tags = item.get("tags") or []
            sentiment = _detect_sentiment(tags)
            symbol = item.get("symbol")
            tickers = _clean_tickers([symbol] if symbol else [], ticker)

            ts_raw = item.get("timestamp") or datetime.utcnow().isoformat()
            try:
                published_at = datetime.fromisoformat(ts_raw)
            except Exception:
                published_at = datetime.utcnow()

            params = {
                "title": item.get("title", "IDX Corporate Filing"),
                "body": item.get("body", ""),
                "source_url": item.get("source") or item.get("url"),
                "thumbnail_url": None,
                "publisher": "IDX",
                "published_at": published_at,
                "tickers": tickers,
                "sector": item.get("sector"),
                "sentiment": sentiment,
                "tags": tags,
                "is_filing": True,
                "raw_payload": json.dumps(item),
            }
            await conn.execute(text(UPSERT_NEWS_SQL), params)
            total_inserted += 1

    logger.info("Successfully synced %d news/filing items for %s", total_inserted, ticker)
    return total_inserted


async def sync_all(tickers: list[str]):
    print(f"\n========================================================")
    print(f" Memulai Sinkronisasi Berita Real-Time untuk {len(tickers)} Saham")
    print(f" Daftar: {', '.join(tickers)}")
    print(f"========================================================\n")

    summary = {}
    for i, t in enumerate(tickers, 1):
        print(f"[{i}/{len(tickers)}] Memproses {t}...")
        try:
            count = await sync_ticker_news(t)
            summary[t] = count
        except Exception as e:
            logger.error("Gagal sinkronisasi %s: %s", t, e)
            summary[t] = f"Error: {e}"
        await asyncio.sleep(0.5)

    engine = get_engine()
    async with engine.connect() as conn:
        res = await conn.execute(text("SELECT COUNT(*) FROM stock_news;"))
        total_in_db = res.scalar()

    print("\n========================================================")
    print(f" SINKRONISASI SELESAI! Total Berita di Database: {total_in_db}")
    print("========================================================")
    for t, cnt in summary.items():
        print(f"  • {t:5s}: {cnt} items")


if __name__ == "__main__":
    import sys
    target = sys.argv[1] if len(sys.argv) > 1 else "remaining"
    
    remaining = ["BBRI", "BMRI", "BBNI", "TLKM", "ASII", "UNVR", "ICBP", "AMRT", "ANTM"]
    all_tickers = ["BBCA"] + remaining

    if target == "remaining":
        asyncio.run(sync_all(remaining))
    elif target == "all":
        asyncio.run(sync_all(all_tickers))
    else:
        asyncio.run(sync_ticker_news(target))

