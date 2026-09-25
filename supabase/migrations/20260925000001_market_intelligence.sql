-- Market Intelligence: AI-generated daily insights per analysis type.
CREATE TABLE IF NOT EXISTS market_intelligence (
    id SERIAL PRIMARY KEY,
    analysis_type VARCHAR(50) NOT NULL,  -- 'technical', 'sentiment', 'macro'
    label VARCHAR(100) NOT NULL,         -- Display label e.g. "Technical Analysis"
    content TEXT NOT NULL,
    generated_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (analysis_type, generated_date)
);

CREATE INDEX IF NOT EXISTS idx_mi_date ON market_intelligence(generated_date DESC);
