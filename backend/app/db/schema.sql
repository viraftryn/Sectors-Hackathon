-- Invelio database schema for PostgreSQL / Supabase
-- Owner: Person C (Surya)

-- Cached stock metadata from Sectors API
CREATE TABLE IF NOT EXISTS stocks (
    ticker VARCHAR(10) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    sector VARCHAR(100),
    subsector VARCHAR(100),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- AI-generated stock scores and recommendations
CREATE TABLE IF NOT EXISTS scores (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker),
    fundamental_score FLOAT,
    macro_score FLOAT,
    sector_score FLOAT,
    risk_score FLOAT,
    sentiment_score FLOAT,
    overall_score FLOAT,
    recommendation VARCHAR(10),
    reasoning TEXT,
    scored_at TIMESTAMP DEFAULT NOW()
);

-- Conversation logs for the chatbot
CREATE TABLE IF NOT EXISTS chat_history (
    id SERIAL PRIMARY KEY,
    session_id UUID NOT NULL,
    role VARCHAR(20) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- User & Device installations (Unique ID per app install)
CREATE TABLE IF NOT EXISTS user_installations (
    device_id VARCHAR(64) PRIMARY KEY,
    device_name VARCHAR(100),
    os_version VARCHAR(50),
    app_version VARCHAR(20) DEFAULT '1.0.0',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_active_at TIMESTAMPTZ DEFAULT NOW()
);

-- User's stock holdings (linked to unique device ID)
CREATE TABLE IF NOT EXISTS user_holdings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(64) NOT NULL REFERENCES user_installations(device_id) ON DELETE CASCADE,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker) ON DELETE RESTRICT,
    stock_name VARCHAR(200),
    market VARCHAR(20) NOT NULL DEFAULT 'IDX',
    currency VARCHAR(10) NOT NULL DEFAULT 'IDR',
    shares NUMERIC(15, 4) NOT NULL,
    price_per_share NUMERIC(15, 2) NOT NULL,
    total_invested NUMERIC(18, 2) NOT NULL,
    buy_date TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Legacy portfolio table for backwards compatibility
CREATE TABLE IF NOT EXISTS portfolio (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker),
    shares INTEGER NOT NULL,
    buy_price FLOAT NOT NULL,
    added_at TIMESTAMP DEFAULT NOW()
);

-- Agent-generated notifications
CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker),
    alert_type VARCHAR(30) NOT NULL,
    severity VARCHAR(10) NOT NULL DEFAULT 'medium',
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Cached Sectors API responses (credit-saving) — Owner: Person A (Vira)
CREATE TABLE IF NOT EXISTS sectors_cache (
    cache_key VARCHAR(200) PRIMARY KEY,
    data JSONB NOT NULL,
    ttl INTEGER NOT NULL,
    cached_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_scores_ticker ON scores(ticker);
CREATE INDEX IF NOT EXISTS idx_scores_scored_at ON scores(scored_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_session ON chat_history(session_id);
CREATE INDEX IF NOT EXISTS idx_alerts_ticker ON alerts(ticker);
CREATE INDEX IF NOT EXISTS idx_alerts_unread ON alerts(is_read) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_cache_cached_at ON sectors_cache(cached_at);
