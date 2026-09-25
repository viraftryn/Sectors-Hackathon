# Invelio — Agentic AI for Indonesian Stock Analysis

Powered by [Sectors API](https://sectors.app) | Sectors Hackathon 2026

An iOS SwiftUI app backed by a Python agentic backend: a LangGraph scoring agent, a tool-calling
chatbot, and market alerts. Every number in the app comes from the Sectors Financial API v2 —
remove Sectors and the scoring, the chatbot and the alerts all stop working.

## Architecture

```
            iOS app (SwiftUI)
                   │  REST + SSE
┌──────────────────▼───────────────────────────────────────────┐
│ FastAPI backend                                              │
│                                                              │
│  routes: /stocks /stock/{ticker} /market-overview            │
│          /recommendations /scoring/run /chat /chat/stream     │
│          /alerts /portfolio /cache/stats /status             │
│                                                              │
│  agents (LangGraph):                                         │
│    Scoring   fetch_market_data → compute_scores → llm_reasoning │
│    Chatbot   classify_question → retrieve_context → generate  │
│    Alert     fetch_market_data → detect_anomalies → generate  │
│                                                              │
│  CachedSectorsClient ──► cache: memory (L1) → PostgreSQL (L2) │
│         │                                                     │
│         └──► SectorsClient ──► Sectors API v2                 │
└──────────────────┬───────────────────────────────────────────┘
                   │
        Supabase (PostgreSQL): stocks, stock_scores, alerts,
        chat_history, user_installations, user_holdings, sectors_cache
```

The LLM (Gemini) is used inside agent nodes for reasoning and tool selection, not as the
orchestrator. The graphs decide the order of work; the LLM decides what to say and, in the
chatbot, which Sectors endpoints are worth calling.

## Agents

### Scoring Agent (`backend/app/agents/scoring.py`)

Ranks the tracked stocks daily on five components, each 0-100 (higher is better, so a high risk
score means low risk). Weights: fundamental 30%, macro 15%, sector 20%, risk 15%, sentiment 20%.

| Component | Sectors data | Method |
|---|---|---|
| Fundamental | screener (`/companies/`), subsector report | PE vs subsector median PE, PBV, ROE, DER (skipped for banks), dividend yield |
| Macro | `/index-daily/ihsg/`, `/foreign-flow/IHSG/` | IHSG trend + net foreign flow share of turnover |
| Sector | `/subsector/report/{slug}/` | subsector 1-week market cap change vs IHSG |
| Risk | `/daily/{ticker}/` | annualised volatility and max drawdown |
| Sentiment | `/news/`, `/filings/` | Bullish/Bearish tags + insider buy/sell value |

`llm_reasoning` sends the scores to Gemini, which returns BUY/HOLD/SELL plus 2-3 sentences of
reasoning. If Gemini is unavailable the agent falls back to a rule-based label (BUY ≥ 65,
SELL ≤ 40) and a generated summary, so the endpoint never fails because of the LLM.

### Chatbot Agent (`backend/app/agents/chatbot.py`)

`classify_question` labels the question and extracts tickers; `retrieve_context` lets the LLM pick
Sectors tools (company report, prices, news, insider filings, sector report, index, movers, most
traded, stock list) over up to three rounds; `generate_response` answers using only the retrieved
data. Questions about untracked tickers are refused before any Sectors call.

The tools come from one of two sources, set by `USE_MCP`:

- **Sectors MCP server** (`USE_MCP=true`, used for the demo): the LLM calls the hosted Sectors MCP
  tools directly. A guard pins company-report sections and top-mover periods and rejects untracked
  tickers, so a question cannot trigger an expensive call.
- **REST + cache** (`USE_MCP=false`, development): the same tools wrap `CachedSectorsClient`, so
  repeated questions cost nothing.

### Alert Agent (`backend/app/agents/alert.py`)

`fetch_market_data` reads top movers, most traded stocks and news; `detect_anomalies` flags tracked
stocks that moved more than 3% (medium) or 5% (high), entered the most-traded list, or appear in
news tagged Bearish, Downgrade, Lawsuit and similar; `generate_alerts` writes them to the `alerts`
table, skipping duplicates from the same day. `POST /api/alerts/scan` runs it.

## Sectors API and the credit budget

The project has 1,000 API credits for development, testing and the demo, so the backend is built
around not spending them.

- **Mock first.** `USE_MOCK_DATA=true` (default) serves saved v2-shaped responses from
  `backend/app/mock_data/sectors/`, one file per cache key. Zero credits while building.
- **Two-layer cache.** Memory → PostgreSQL → Sectors. TTL per data type: prices 5 min, index
  10 min, news 15 min, sector reports and filings 1 hour, fundamentals 24 hours.
  `GET /api/cache/stats` reports hits, misses and credits saved.
- **Cheap calls by construction.** The screener returns ratios and the latest close for all
  tracked tickers in one call (1 credit) instead of one report per ticker (8 credits each).
  Sections and periods are always pinned, since Sectors bills per section and per period.
- **Throttled scoring.** `POST /api/scoring/run` runs at most once an hour and is serialized, so
  concurrent triggers cannot pay twice. One cold run costs about 45 credits.
- **Degrade, never fail.** If Sectors errors, the client serves the last good response for that
  resource; the market overview drops its secondary panels rather than the whole screen.

## API

See [backend/API_CONTRACT.md](backend/API_CONTRACT.md) for request and response shapes.

| Endpoint | Purpose |
|---|---|
| `GET /api/stocks` | tracked stocks with price, change, sector |
| `GET /api/stock/{ticker}` | fundamentals + 90 days of prices |
| `GET /api/market-overview` | IHSG, foreign flow, movers, most traded |
| `GET /api/recommendations` | latest AI scores and reasoning |
| `POST /api/scoring/run` | run the Scoring Agent (throttled) |
| `POST /api/chat`, `POST /api/chat/stream` | chatbot, plain JSON or SSE |
| `GET /api/alerts`, `POST/PATCH /api/alerts/{id}/read` | alert feed, per device |
| `POST /api/alerts/scan` | run the Alert Agent |
| `GET/POST /api/portfolio/lots` (`/portfolio/buy`), `POST /api/portfolio/sell`, `DELETE /api/portfolio/lots/{id}`, `GET /api/portfolio` | holdings, FIFO sells and P&L, per device |
| `GET /api/status`, `GET /api/cache/stats` | health, mock mode, credit usage |

Portfolio and alert endpoints identify the user with an `X-Device-Id` header.

## Project Structure

```
├── backend/                 # Python FastAPI backend
│   ├── app/
│   │   ├── api/routes/      # API endpoints
│   │   ├── agents/          # LangGraph agents (scoring, chatbot, alert)
│   │   ├── clients/         # Sectors v2 client, cached wrapper, Gemini
│   │   ├── db/              # database session + queries
│   │   ├── mock_data/       # saved Sectors responses for development
│   │   ├── models/          # Pydantic schemas
│   │   └── cache.py         # two-layer cache (memory + PostgreSQL)
│   ├── scripts/             # operational scripts (real-data smoke test)
│   └── tests/               # backend tests
├── ios/Invelio/             # iOS SwiftUI app
│   ├── Sources/
│   │   ├── App/             # app entry point & tab navigation
│   │   ├── Views/           # SwiftUI views (Home, Portfolio, Chat, Alerts)
│   │   ├── Models/          # data models
│   │   ├── Services/        # API client & networking
│   │   └── Components/      # reusable UI components
│   └── Tests/               # iOS unit tests
├── supabase/migrations/     # database schema
└── .github/workflows/       # CI pipelines
```

## Getting Started

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env          # add SECTORS_API_KEY, GEMINI_API_KEY, DATABASE_URL
uvicorn app.main:app --reload
```

Interactive docs at `http://localhost:8000/docs`. `USE_MOCK_DATA=true` keeps every Sectors call
offline; the database is still needed for the cache and for stored scores, portfolios and chats.

Tests never call Sectors or Gemini:

```bash
pytest            # 106 tests
ruff check app tests && ruff format --check app tests && mypy app --ignore-missing-imports
```

Checking real data (spends credits, prints the cost of each stage):

```bash
python scripts/smoke_real.py stocks     # ~1 credit
python scripts/smoke_real.py market     # ~6 credits
python scripts/smoke_real.py scoring    # ~47 credits, writes to the database
```

### Deploying

`backend/Dockerfile` builds the API for any container host.
[backend/DEPLOY_AND_DEMO.md](backend/DEPLOY_AND_DEMO.md) covers environment variables, the Supabase
connection string, and the steps to run before recording the demo.

### iOS

```bash
cd ios/Invelio
xcodegen generate
open Invelio.xcodeproj
```

Requires Xcode 16+ and iOS 17+ deployment target. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) via `brew install xcodegen`.

## Tech Stack

- **Backend:** Python 3.12, FastAPI, LangGraph, Gemini (google-genai / langchain-google-genai)
- **iOS:** SwiftUI (iOS 17+), Swift Charts, Swift Concurrency
- **Data:** Sectors Financial API v2
- **Database:** PostgreSQL via Supabase
- **Caching:** in-memory + PostgreSQL, TTL-based
- **CI:** GitHub Actions (ruff + mypy + pytest, xcodebuild, Supabase migrations)
