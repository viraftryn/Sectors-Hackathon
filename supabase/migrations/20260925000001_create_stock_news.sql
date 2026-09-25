-- ============================================================================
-- INVELIO SUPABASE MIGRATION: 20260925000001_create_stock_news.sql
-- Stock News Feed & IDX Filings Table
-- ============================================================================

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

-- Indexes for lightning fast feed queries and ticker filtering
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_news_source_title ON stock_news (COALESCE(source_url, ''), title);
CREATE INDEX IF NOT EXISTS idx_stock_news_published ON stock_news (published_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_news_tickers ON stock_news USING GIN (tickers);
