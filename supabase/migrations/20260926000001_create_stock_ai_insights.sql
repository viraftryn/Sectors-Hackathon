-- ============================================================================
-- INVELIO SUPABASE MIGRATION: 20260926000001_create_stock_ai_insights.sql
-- Daily AI-Generated Stock Insights per Ticker
-- Categories: 'technical', 'fundamentals', 'sentiment', 'outlook'
-- ============================================================================

CREATE TABLE IF NOT EXISTS stock_ai_insights (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(10) NOT NULL REFERENCES stocks(ticker) ON DELETE CASCADE,
    analysis_type VARCHAR(50) NOT NULL,  -- 'technical', 'fundamentals', 'sentiment', 'outlook'
    label VARCHAR(100) NOT NULL,         -- 'Technical Analysis', 'Fundamentals', 'Market Sentiment', 'Outlook & Risks'
    content TEXT NOT NULL,
    generated_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (ticker, analysis_type, generated_date)
);

CREATE INDEX IF NOT EXISTS idx_stock_ai_insights_ticker_date ON stock_ai_insights(ticker, generated_date DESC);

-- Enable Row Level Security
ALTER TABLE stock_ai_insights ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'stock_ai_insights' AND policyname = 'Allow public read on stock_ai_insights'
    ) THEN
        CREATE POLICY "Allow public read on stock_ai_insights"
        ON stock_ai_insights FOR SELECT
        USING (true);
    END IF;
END $$;
