# Invelio — Agentic AI for Indonesian Stock Analysis (IDX)

> **Sectors Hackathon 2026 Project**  
> An autonomous multi-agent financial platform for the Indonesia Stock Exchange (IDX), combining **LangGraph agentic orchestration**, **Google Gemini AI**, and deep native integration with **Sectors Financial API v2 & Sectors MCP Server**.

[![Python 3.12](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![LangGraph](https://img.shields.io/badge/LangGraph-0.2+-FF6F00?logo=langchain&logoColor=white)](https://langchain-ai.github.io/langgraph/)
[![Sectors API](https://img.shields.io/badge/Data-Sectors%20API%20v2%20%26%20MCP-0052CC)](https://sectors.app)
[![iOS 17+](https://img.shields.io/badge/iOS-17.0+-000000?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Swift%206-F05138?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Supabase](https://img.shields.io/badge/Database-Supabase%20PostgreSQL-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)

---

## 📌 Executive Summary

**Invelio** bridges the gap between raw, fragmented financial metrics and retail investor decisions on the Indonesia Stock Exchange (IDX). By fusing **deterministic quantitative models** with **autonomous LLM cognitive agents**, Invelio turns thousands of data points into actionable insights, real-time anomaly alerts, and conversational equity research.

Every single datapoint—from valuation ratios, 90-day OHLCV price histories, foreign fund flows, corporate actions, and insider filings to top-mover rankings—originates from the **[Sectors Financial API v2](https://sectors.app)** and the **Sectors MCP Server**.

---

## 🏛️ System Architecture

![Invelio Layer & Flow](./Invelio%20Layer%20%26%20Flow.png)

```mermaid
flowchart TB
    subgraph iOS_Client["📱 iOS Client (SwiftUI + Swift Charts)"]
        UI_Home["Home Screen\n(Market Overview, Movers)"]
        UI_Stock["Stock Detail\n(Interactive Charts, AI Insights)"]
        UI_Chat["AI Chatbot\n(SSE Token Streaming)"]
        UI_Alerts["Market Alerts & Anomaly Feed"]
        UI_Portfolio["Virtual Portfolio\n(FIFO Lots, Realized P&L)"]
    end

    iOS_Client -->|REST & SSE (HTTP/2)| API_Gateway

    subgraph Backend["⚡ FastAPI Backend Service"]
        API_Gateway["FastAPI Gateway\n(/api/stocks, /api/chat, etc.)"]

        subgraph LangGraph_Engine["🤖 LangGraph Autonomous Agent Engine"]
            ScoringAgent["<b>Scoring Agent</b>\n5-Pillar Score Matrix + LLM Reasoning"]
            ChatbotAgent["<b>Chatbot Agent</b>\n3-Node ReAct Cycle + MCP/REST Tool Calling"]
            AlertAgent["<b>Alert Agent</b>\nDeterministic Volatility & Anomaly Scanner"]
            MarketIntelAgent["<b>Market Intelligence</b>\nDaily Macro, Sentiment & Tech Synthesis"]
            StockIntelAgent["<b>Stock AI Insights</b>\n4-Pillar In-Depth Ticker Research"]
        end

        subgraph Caching_Engine["🛡️ Intelligent Dual-Layer Cache Engine"]
            L1["L1: In-Memory TTL Cache"]
            L2["L2: PostgreSQL sectors_cache Table"]
        end

        API_Gateway --> LangGraph_Engine
        LangGraph_Engine --> Caching_Engine
    end

    subgraph LLM_Providers["🧠 Cognitive Intelligence Layer"]
        Gemini["Google Gemini (google-genai / AI Studio)"]
        OpenAI["OpenAI GPT-4o (Fallback)"]
    end

    subgraph Sectors_Data_Engine["🌐 Sectors.app Data Backbone"]
        SectorsREST["Sectors Financial API v2\n(REST: Screener, Prices, Flow, Reports)"]
        SectorsMCP["Sectors MCP Server\n(Streamable HTTP / Model Context Protocol)"]
    end

    subgraph Database["🗄️ Supabase PostgreSQL Engine"]
        DB_Tables[("stocks\nstock_daily_prices\nstock_scores\nstock_insights\nalerts\nuser_holdings / trades\nchat_history\nsectors_cache")]
    end

    LangGraph_Engine --> LLM_Providers
    Caching_Engine -->|Cache Miss| SectorsREST
    ChatbotAgent -->|USE_MCP=true| SectorsMCP
    Backend --> Database
```

---

## 🌐 Sectors.app as the Core Data Source (API & MCP)

The platform is designed ground-up around **Sectors.app**. Without Sectors, the scoring, chatbot, stock details, and anomaly detection cannot function. 

### 1. Dual Integration Modes: REST API & MCP Server

Invelio provides first-class support for both programmatic REST calls and dynamic tool-calling via the **Model Context Protocol (MCP)**:

| Feature | Sectors REST API v2 (`USE_MCP=false`) | Sectors MCP Server (`USE_MCP=true`) |
|---|---|---|
| **Protocol** | Standard HTTPS JSON REST | Streamable HTTP (`mcp.client.streamable_http`) |
| **Integration** | `CachedSectorsClient` + `SectorsClient` | `langchain_mcp_adapters.tools.load_mcp_tools` |
| **Primary Use** | Scheduled scoring, alerts, stock detail, offline dev | Live interactive Chatbot demo & autonomous tool-calling |
| **Caching** | Native L1 (RAM) + L2 (PostgreSQL) | Wrapped through `_wrap_mcp_tool_cached` |
| **Cost Control** | Batch query screener (1 call for all 10 tickers) | Parameter guards, section pinning & ticker whitelist |

### 2. Sectors Endpoints Utilized

* **Fundamentals & Reports**:
  * `/companies/`: Screener fetching P/E, P/B, ROE, DER, Dividend Yield, and Market Cap across all tracked stocks in a single credit-optimized request.
  * `/company/report/{ticker}/`: Detailed financial breakdowns and balance sheet metrics.
  * `/subsector/report/{sub_sector}/`: Median sector P/E and market cap changes for relative valuation.
* **Pricing & Market Velocity**:
  * `/daily/{ticker}/`: 90-day to 365-day OHLCV historic data used for charting, volatility, and max drawdown.
  * `/companies/top-changes/`: 1-day top gainers and top losers.
  * `/most-traded/`: Liquidity surge detection and institutional volume tracker.
  * `/index-daily/ihsg/` & `/idx-total/`: Macro benchmarks for the Jakarta Composite Index.
* **Capital Flow & Sentiment**:
  * `/foreign-flow/{symbol}/`: Institutional foreign net buy/sell turnover share.
  * `/news/`: Recent 30-day sentiment-tagged media coverage (Bullish, Bearish, etc.).
  * `/filings/`: Corporate insider trading reports and IDX regulatory disclosures.

### 3. Credit-Budget & Defensive Engineering

To operate effectively within a limited hackathon credit budget (1,000 credits), the backend implements enterprise-grade caching and optimization:

1. **Zero-Credit Mock Mode (`USE_MOCK_DATA=true`)**: Full fixture replay from `backend/app/mock_data/sectors/` matching exact v2 responses for all offline development.
2. **Two-Layer Cache (L1 Memory + L2 PostgreSQL)**:
   * **Prices**: 5 min TTL
   * **Market Overview & Index**: 10 min TTL
   * **News & Sentiment**: 15 min TTL
   * **Sector Reports & Filings**: 1 hour TTL
   * **Fundamentals & Corporate Actions**: 24 hours TTL
3. **Transparent MCP Tool Caching**: MCP tool executions are wrapped with dynamic cache key hashing, preventing duplicate credit burns if an LLM queries the same metric multiple times.
4. **Resilient Stale-Response Serving (`_last_good`)**: If Sectors returns HTTP 429, 503, or rate limits, the client transparently returns the last valid response from cache instead of failing.
5. **Throttled Scoring**: The heavy scoring pipeline (`/api/scoring/run`) uses async locks and an hourly rate-limiter, preventing concurrent calls from double-spending credits.

---

## 🤖 Autonomous AI Agents (LangGraph Orchestration)

Invelio uses **LangGraph** (`StateGraph`) as its core orchestration engine. The graphs dictate execution flow and state transitions deterministically, while LLMs (Google Gemini / OpenAI) provide cognitive reasoning, entity extraction, and tool selection.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       LANGGRAPH MULTI-AGENT SUITE                           │
├───────────────────┬───────────────────────────────────┬─────────────────────┤
│ Agent             │ LangGraph State Workflow          │ Cognitive Role      │
├───────────────────┼───────────────────────────────────┼─────────────────────┤
│ Chatbot Agent     │ classify → retrieve → generate    │ Tool Selection & QA │
│ Scoring Agent     │ fetch → compute → llm_reasoning   │ Equity Thesis Synth │
│ Market Intel      │ gather_data → generate_insights   │ Macro Commentary    │
│ Stock Insights    │ SQL aggregation → 4-card synthesis│ Per-Stock Research  │
│ Alert Agent       │ fetch → detect → generate_alerts  │ Rule-Based Anomaly  │
└───────────────────┴───────────────────────────────────┴─────────────────────┘
```

---

### 1. Chatbot Agent (`backend/app/agents/chatbot.py`)

A stateful, tool-calling agent enabling conversational equity research on the IDX.

```mermaid
graph LR
    UserMsg([User Question]) --> ClassifyNode[1. classify_question]
    ClassifyNode --> RetrieveNode[2. retrieve_context]
    RetrieveNode -->|Autonomous Tool Call Loop<br/>max 3 rounds| RetrieveNode
    RetrieveNode -->|Tools: Sectors MCP or REST| GenerateNode[3. generate_response]
    GenerateNode --> Answer([Grounded Answer / SSE Stream])
```

* **State (`ChatState`)**: Tracks `user_message`, `chat_history`, `question_type`, `entities` (tickers), `context`, and `response`.
* **Step 1: `classify_question`**: Parses user intent (valuation, technical, news) and extracts targeted IDX tickers. Rejects untracked tickers early to prevent wasteful API calls.
* **Step 2: `retrieve_context`**: The LLM autonomously chooses which Sectors tools to invoke (`fetch-company-report`, `fetch-daily-price`, `fetch-news`, `fetch-subsector-report`, etc.) over up to 3 iterative rounds.
* **Step 3: `generate_response`**: Synthesizes a factual, grounded response citing only retrieved Sectors data. Supports Server-Sent Events (SSE) token streaming via `/api/chat/stream`.

---

### 2. Scoring Agent (`backend/app/agents/scoring.py`)

A hybrid quantitative-qualitative evaluation pipeline ranking tracked IDX stocks daily.

```mermaid
graph LR
    START([Start]) --> Fetch[1. fetch_market_data]
    Fetch --> Compute[2. compute_scores]
    Compute --> Reason[3. llm_reasoning]
    Reason --> END([Final Scores & Thesis])
```

* **Quantitative Matrix (0–100 scale)**:
  $$\text{Score} = 0.30F + 0.15M + 0.20S + 0.15R + 0.20E$$
  * **Fundamental ($F$ - 30%)**: P/E vs Subsector Median P/E, P/BV, ROE, DER (der waived for banks), and Dividend Yield.
  * **Macro ($M$ - 15%)**: 5-day IHSG momentum + net foreign capital flow share.
  * **Sector ($S$ - 20%)**: Subsector 1-week market cap performance relative to IHSG.
  * **Risk ($R$ - 15%)**: 90-day annualized volatility and maximum drawdown.
  * **Sentiment ($E$ - 20%)**: Ratio of Bullish vs. Bearish news + insider transaction value.
* **Qualitative Synthesis (`llm_reasoning`)**: Gemini analyzes the computed scores and outputs a **BUY** ($\ge 65$), **HOLD**, or **SELL** ($\le 40$) recommendation accompanied by a 2–3 sentence thesis. Fallback heuristics ensure high availability if the LLM is unreachable.

---

### 3. Market Intelligence Agent (`backend/app/agents/market_intelligence.py`)

Generates daily top-level market commentary by reading aggregated data directly from PostgreSQL:
* **Workflow**: `gather_data` $\rightarrow$ `generate_insights`.
* **Outputs 3 Daily Perspectives**:
  1. **Technical Analysis**: Moving averages, price consolidation, and volume levels.
  2. **News Sentiment**: Sentiment balance across media releases and AI scoring trends.
  3. **Macro & Currency**: IHSG momentum, interest rates, and foreign fund flow dynamics.

---

### 4. Stock AI Insights Agent (`backend/app/agents/stock_insights.py`)

Automated daily equity research assistant triggered at 06:00 WIB. For each tracked stock, it reads 365-day price history, corporate metrics, and scores to output 4 structured cards:
* **Technical Analysis**: 30-day highs/lows, support & resistance, volume accumulation.
* **Fundamentals**: Relative valuation, ROE capital efficiency, debt health.
* **Market Sentiment**: AI scoring shifts, news catalysts, institutional appetite.
* **Outlook & Risks**: Upcoming catalysts, macroeconomic tailwinds, and risks.

---

### 5. Alert Agent (`backend/app/agents/alert.py`)

A pure deterministic LangGraph pipeline detecting anomalies across IDX trading hours:
* **Workflow**: `fetch_market_data` $\rightarrow$ `detect_anomalies` $\rightarrow$ `generate_alerts`.
* **Triggers**:
  * Price changes exceeding **±3% (Medium)** or **±5% (High)**.
  * Unusual volume spikes landing a stock in the Top-5 Most Traded list.
  * High-risk news tags (*Bearish*, *Lawsuit*, *Scandal*, *Default*, *Downgrade*).
* **Execution**: Scheduled automatically on weekdays during IDX market hours (09:00–16:00 WIB), with deduplication to prevent alert fatigue.

---

## 📱 iOS SwiftUI Native Application

Built using modern **Swift 6 & SwiftUI** (iOS 17+ target):
* **Home Dashboard**: Live market index, top gainers/losers carousel, AI recommendation leaders, and quick market pulse.
* **Interactive Stock Detail**: Smooth Swift Charts with time-frame selectors (1W, 1M, 3M, 1Y), key fundamental ratios, and the 4 AI Insight cards.
* **AI Chatbot Interface**: Conversational interface with markdown formatting, ticker tags, quick suggestion chips, and real-time streaming tokens.
* **Smart Alerts & Notifications**: Real-time push-style anomaly feed filterable by severity and stock.
* **Virtual Portfolio Tracker**: Multi-lot transaction ledger supporting **FIFO (First-In, First-Out)** accounting, average cost calculation, and realized vs. unrealized P&L.

---

## 🛠️ Complete Tech Stack

```
Layer                   Technologies
───────────────────────────────────────────────────────────────────────────
Backend Service         Python 3.12, FastAPI, Uvicorn, Pydantic v2
Agentic Orchestration   LangGraph (0.2+), LangChain Core
Cognitive LLM Layer     Google Gemini 2.5/3.5 (google-genai), OpenAI GPT-4o
Data & Tool Layer       Sectors Financial API v2, Sectors MCP Server (SSE/HTTP)
MCP Adapters            langchain-mcp-adapters, mcp SDK
Database & ORM          Supabase (PostgreSQL 16), SQLAlchemy 2.0 (asyncpg)
Caching Engine          L1 In-Memory + L2 PostgreSQL (sectors_cache)
iOS Mobile App          Swift 6, SwiftUI, Swift Charts, Swift Concurrency
DevOps & Quality        Docker, GitHub Actions CI, Pytest, Ruff, Mypy, XcodeGen
```

---

## 🚀 Getting Started

### Prerequisites

* Python 3.12+
* Xcode 16+ & iOS 17+ SDK (for iOS app)
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
* Docker (optional, for containerized run)

### 1. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements-dev.txt

# Configure environment
cp .env.example .env
```

Edit `backend/.env` with your API credentials:
```env
SECTORS_API_KEY="your-sectors-api-key"
GEMINI_API_KEY="your-gemini-api-key"
DATABASE_URL="postgresql+asyncpg://postgres:[password]@db.[ref].supabase.co:5432/postgres"

# Development flags
USE_MOCK_DATA=true       # true: 0 credits used (mock fixtures)
USE_MCP=false            # true: use Sectors MCP Server; false: REST + Cache
```

Run the backend server:
```bash
uvicorn app.main:app --reload --port 8000
```
* Interactive API Documentation: `http://localhost:8000/docs`
* Status & Health Check: `http://localhost:8000/api/status`

### 2. Running Quality Checks & Tests

```bash
# Run 100+ automated unit & integration tests
pytest

# Linting and Type Checking
ruff check app tests
ruff format --check app tests
mypy app --ignore-missing-imports
```

### 3. iOS Application Setup

```bash
cd ios/Invelio

# Generate Xcode project from project.yml specification
xcodegen generate

# Open in Xcode
open Invelio.xcodeproj
```

* In `ios/Invelio/Sources/Services/APIClient.swift`, configure `baseURL` (defaults to `http://localhost:8000/api` for Simulator).
* Select target device (iPhone 15/16 Pro running iOS 17+) and hit **Cmd + R**.

---

## 📑 API Reference Overview

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/stocks` | Tracked stock list with latest prices & changes |
| `GET` | `/api/stock/{ticker}` | Comprehensive fundamentals & 1-year OHLCV prices |
| `GET` | `/api/stock/{ticker}/insights` | Daily 4-card AI equity research report |
| `GET` | `/api/market-overview` | Macro index, foreign flows, and top gainers/losers |
| `GET` | `/api/market-intelligence` | Daily AI market commentary (Macro, Technical, News) |
| `GET` | `/api/recommendations` | Latest 5-pillar AI scores and BUY/HOLD/SELL thesis |
| `POST` | `/api/scoring/run` | Execute LangGraph Scoring Agent (Rate-limited) |
| `POST` | `/api/chat` | Non-streaming Chatbot completion |
| `POST` | `/api/chat/stream` | Token-by-token Chatbot response (Server-Sent Events) |
| `GET` | `/api/alerts` | Anomaly alert feed (Scoped by `X-Device-Id`) |
| `POST` | `/api/alerts/scan` | Trigger LangGraph anomaly detection run |
| `GET` | `/api/portfolio` | Holdings summary, total valuation, and P&L |
| `POST` | `/api/portfolio/buy` | Add buy lot to simulated portfolio |
| `POST` | `/api/portfolio/sell` | FIFO sell execution |
| `GET` | `/api/cache/stats` | Cache hit/miss metrics and saved credit tally |
| `GET` | `/api/status` | System health and data mode verification |

---

## 👥 Tracked Universe (IDX Top 10)

The system focuses on Indonesia's most liquid, blue-chip market leaders:
* **Banking & Financials**: `BBCA`, `BBRI`, `BMRI`, `BBNI`
* **Telecommunications & Infrastructure**: `TLKM`
* **Conglomerate & Industrials**: `ASII`
* **Consumer Staples**: `UNVR`, `ICBP`, `AMRT`
* **Commodities & Mining**: `ANTM`

---

## 📊 Invelio Agentic AI vs. IHSG Benchmark

![Invelio Backtesting](./Invelio_backtesting_chart_new.jpeg)

Berikut adalah perbandingan performa antara **INVELIO AI Recommendation (Top 5 Balanced)** dengan **IHSG Benchmark (^JKSE)** berdasarkan indikator keuangan utama:

| Indikator | INVELIO AI Recommendation (Top 5 Balanced) | IHSG Benchmark (^JKSE) | Keunggulan INVELIO ($\alpha$) |
| :--- | :---: | :---: | :---: |
| **Total Pertumbuhan (5 Tahun)** | +24.78% | -8.90% | **+33.68%** (Net Alpha) |
| **CAGR (Pertumbuhan Tahunan)** | +5.13% | -1.96% | **+7.09%** / tahun |
| **Maximum Drawdown (MDD)** | -31.37% | -41.52% | **10.15%** lebih tahan banting |
| **Sharpe Ratio (Risk-Adjusted)** | +0.11 | -0.32 | Jauh lebih stabil |

## 📄 License & Attribution

Developed for the **Sectors Hackathon 2026**.  
Financial data and MCP tooling provided exclusively by **[Sectors.app](https://sectors.app)**.
