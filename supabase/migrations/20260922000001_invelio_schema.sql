-- ============================================================================
-- INVELIO SUPABASE POSTGRESQL SCHEMA MIGRATION
-- Multi-Device Portfolio + Sectors API v2 Data Engine
-- ============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 2. USER & DEVICE INSTALLATION (Unique ID per app install)
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_installations (
    device_id VARCHAR(64) PRIMARY KEY, -- UIDevice identifierForVendor or UUID
    device_name VARCHAR(100),          -- e.g. "iPhone 16 Pro"
    os_version VARCHAR(50),           -- e.g. "iOS 18.0"
    app_version VARCHAR(20) DEFAULT '1.0.0',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 3. STOCKS REFERENCE & FUNDAMENTALS (Matching Backend API Endpoint Schema)
--    Endpoint: GET /api/stocks & GET /api/stock/{ticker}
-- ============================================================================
CREATE TABLE IF NOT EXISTS stocks (
    ticker VARCHAR(10) PRIMARY KEY,              -- e.g. "BBCA"
    symbol VARCHAR(15) NOT NULL,                 -- e.g. "BBCA.JK"
    name VARCHAR(200) NOT NULL,                  -- e.g. "PT Bank Central Asia Tbk."
    sector VARCHAR(100),                         -- e.g. "Financials"
    sub_sector VARCHAR(100),                     -- e.g. "Banks"
    price NUMERIC(15, 2) NOT NULL DEFAULT 0.0,   -- last_close_price
    change_pct NUMERIC(6, 2) DEFAULT 0.0,        -- daily_close_change (%)
    market_cap NUMERIC(24, 2),                   -- market_cap in IDR
    
    -- Fundamentals (Sectors API v2 official metrics)
    pe_ttm NUMERIC(10, 2),                       -- Price to Earnings (TTM)
    pb_mrq NUMERIC(10, 2),                       -- Price to Book (MRQ)
    roe_ttm NUMERIC(8, 2),                       -- Return on Equity (TTM, in %)
    der_mrq NUMERIC(10, 2),                      -- Debt to Equity Ratio
    yield_ttm NUMERIC(8, 2),                     -- Dividend Yield (TTM, in %)
    
    -- 52-Week Range
    week52_high NUMERIC(15, 2),
    week52_low NUMERIC(15, 2),
    
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed 10 Saham Utama yang di-track backend
INSERT INTO stocks (ticker, symbol, name, sector, sub_sector, updated_at)
VALUES 
    ('BBCA', 'BBCA.JK', 'PT Bank Central Asia Tbk.', 'Financials', 'Banks', NOW()),
    ('BBRI', 'BBRI.JK', 'PT Bank Rakyat Indonesia (Persero) Tbk', 'Financials', 'Banks', NOW()),
    ('BMRI', 'BMRI.JK', 'PT Bank Mandiri (Persero) Tbk', 'Financials', 'Banks', NOW()),
    ('BBNI', 'BBNI.JK', 'PT Bank Negara Indonesia (Persero) Tbk', 'Financials', 'Banks', NOW()),
    ('TLKM', 'TLKM.JK', 'PT Telkom Indonesia (Persero) Tbk', 'Infrastructures', 'Telecommunication', NOW()),
    ('ASII', 'ASII.JK', 'Astra International Tbk', 'Industrials', 'Multi-sector Holdings', NOW()),
    ('UNVR', 'UNVR.JK', 'Unilever Indonesia Tbk', 'Consumer Non-Cyclicals', 'Nondurable Household Products', NOW()),
    ('ICBP', 'ICBP.JK', 'Indofood CBP Sukses Makmur Tbk', 'Consumer Non-Cyclicals', 'Food & Beverage', NOW()),
    ('AMRT', 'AMRT.JK', 'Sumber Alfaria Trijaya Tbk', 'Consumer Non-Cyclicals', 'Food & Staples Retailing', NOW()),
    ('ANTM', 'ANTM.JK', 'Aneka Tambang Tbk', 'Basic Materials', 'Basic Materials', NOW())
ON CONFLICT (ticker) DO UPDATE SET
    symbol = EXCLUDED.symbol,
    name = EXCLUDED.name,
    sector = EXCLUDED.sector,
    sub_sector = EXCLUDED.sub_sector,
    updated_at = NOW();

-- ============================================================================
-- 4. USER PORTFOLIO HOLDINGS (Per Device / Installation Unique ID)
--    Matching HoldingLot.swift in iOS
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_holdings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(64) NOT NULL REFERENCES user_installations(device_id) ON DELETE CASCADE,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker) ON DELETE RESTRICT,
    stock_name VARCHAR(200),
    market VARCHAR(20) NOT NULL DEFAULT 'IDX',
    currency VARCHAR(10) NOT NULL DEFAULT 'IDR',
    shares NUMERIC(15, 4) NOT NULL CHECK (shares > 0),             -- Jumlah lembar
    price_per_share NUMERIC(15, 2) NOT NULL CHECK (price_per_share > 0), -- Harga beli per lembar
    total_invested NUMERIC(18, 2) NOT NULL,                         -- Total modal beli
    buy_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 5. DAILY PRICE HISTORY (Grafik Saham 90 Hari)
--    Endpoint: GET /daily/{ticker}/
-- ============================================================================
CREATE TABLE IF NOT EXISTS stock_daily_prices (
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker) ON DELETE CASCADE,
    date DATE NOT NULL,
    open NUMERIC(15, 2),
    high NUMERIC(15, 2),
    low NUMERIC(15, 2),
    close NUMERIC(15, 2) NOT NULL,
    volume BIGINT,
    PRIMARY KEY (ticker, date)
);

-- ============================================================================
-- 6. MARKET OVERVIEW CACHE (IHSG, Gainers/Losers, Foreign Flow)
--    Endpoint: GET /api/market-overview
-- ============================================================================
CREATE TABLE IF NOT EXISTS market_overview_cache (
    id VARCHAR(50) PRIMARY KEY DEFAULT 'latest',
    ihsg_value NUMERIC(12, 2),
    ihsg_change_pct NUMERIC(6, 2),
    ihsg_date DATE,
    foreign_inflow NUMERIC(20, 2),
    foreign_flow_date DATE,
    top_gainers JSONB,
    top_losers JSONB,
    most_traded JSONB,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 7. L2 CACHE (Hemat Kredit Sectors API)
-- ============================================================================
CREATE TABLE IF NOT EXISTS sectors_cache (
    cache_key VARCHAR(200) PRIMARY KEY,
    data JSONB NOT NULL,
    ttl INTEGER NOT NULL,
    cached_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 8. CHAT HISTORY (Agentic AI Chatbot per Device / Sesi)
-- ============================================================================
CREATE TABLE IF NOT EXISTS chat_history (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(64) REFERENCES user_installations(device_id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 9. AI RECOMMENDATION SCORES & ALERTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS stock_scores (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker) ON DELETE CASCADE,
    fundamental_score NUMERIC(5, 2),
    macro_score NUMERIC(5, 2),
    sector_score NUMERIC(5, 2),
    risk_score NUMERIC(5, 2),
    sentiment_score NUMERIC(5, 2),
    overall_score NUMERIC(5, 2),
    recommendation VARCHAR(20),  -- e.g. "BUY", "HOLD", "SELL"
    reasoning TEXT,
    scored_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(64) REFERENCES user_installations(device_id) ON DELETE CASCADE,
    ticker VARCHAR(10) REFERENCES stocks(ticker) ON DELETE CASCADE,
    alert_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'medium',
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 10. INDEXES (Untuk Kecepatan Query Tinggi)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_user_holdings_device ON user_holdings(device_id);
CREATE INDEX IF NOT EXISTS idx_user_holdings_ticker ON user_holdings(ticker);
CREATE INDEX IF NOT EXISTS idx_daily_prices_ticker_date ON stock_daily_prices(ticker, date DESC);
CREATE INDEX IF NOT EXISTS idx_chat_device_session ON chat_history(device_id, session_id);
CREATE INDEX IF NOT EXISTS idx_cache_cached_at ON sectors_cache(cached_at);
CREATE INDEX IF NOT EXISTS idx_scores_ticker ON stock_scores(ticker, scored_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_device_unread ON alerts(device_id, is_read) WHERE is_read = FALSE;

-- ============================================================================
-- 11. CALCULATED VIEW: PORTFOLIO SUMMARY PER DEVICE
-- ============================================================================
CREATE OR REPLACE VIEW view_user_portfolio_summary AS
SELECT 
    h.device_id,
    h.ticker,
    s.name AS stock_name,
    s.sector,
    SUM(h.shares) AS total_shares,
    SUM(h.total_invested) AS total_cost,
    ROUND(SUM(h.total_invested) / NULLIF(SUM(h.shares), 0), 2) AS avg_buy_price,
    s.price AS current_price,
    ROUND(SUM(h.shares) * s.price, 2) AS current_value,
    ROUND((SUM(h.shares) * s.price) - SUM(h.total_invested), 2) AS unrealized_pnl,
    ROUND((((SUM(h.shares) * s.price) - SUM(h.total_invested)) / NULLIF(SUM(h.total_invested), 0)) * 100, 2) AS unrealized_pnl_pct
FROM user_holdings h
JOIN stocks s ON h.ticker = s.ticker
GROUP BY h.device_id, h.ticker, s.name, s.sector, s.price;

-- ============================================================================
-- 12. ROW LEVEL SECURITY (RLS)
-- ============================================================================
ALTER TABLE user_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_holdings ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    -- Note: user_holdings, user_installations, chat_history, and alerts
    -- are private to the backend service and not exposed to public PostgREST anon role.
    -- Table RLS is enabled; direct PostgREST anon access is restricted.

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'stocks' AND policyname = 'Allow public read on stocks'
    ) THEN
        CREATE POLICY "Allow public read on stocks"
        ON stocks FOR SELECT
        USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'stock_daily_prices' AND policyname = 'Allow public read on daily prices'
    ) THEN
        CREATE POLICY "Allow public read on daily prices"
        ON stock_daily_prices FOR SELECT
        USING (true);
    END IF;
END $$;
