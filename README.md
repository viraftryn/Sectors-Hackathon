# Invelio — Agentic AI for Indonesian Stock Analysis

Powered by [Sectors API](https://sectors.app) | Sectors Hackathon 2026

An iOS SwiftUI app backed by a Python agentic backend with LangGraph scoring, AI-powered chatbot via Sectors MCP, and real-time sentiment alerts.

## Project Structure

```
├── backend/                 # Python FastAPI backend
│   ├── app/
│   │   ├── api/routes/      # API endpoints
│   │   ├── agents/          # LangGraph AI agents (scoring, chatbot, alert)
│   │   ├── clients/         # Sectors API client + cached wrapper
│   │   ├── db/              # Database setup & schema
│   │   ├── mock_data/       # Mock API responses for development
│   │   ├── models/          # Pydantic schemas
│   │   └── cache.py         # Two-layer caching (in-memory + PostgreSQL)
│   └── tests/               # Backend tests
├── ios/Invelio/             # iOS SwiftUI app
│   ├── Sources/
│   │   ├── App/             # App entry point & tab navigation
│   │   ├── Views/           # SwiftUI views (Home, Portfolio, Chat, Alerts)
│   │   ├── Models/          # Data models
│   │   ├── Services/        # API client & networking
│   │   └── Components/      # Reusable UI components
│   └── Tests/               # iOS unit tests
└── .github/workflows/       # CI pipelines
```

## Getting Started

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
# Edit .env with your API keys and Supabase credentials
uvicorn app.main:app --reload
```

### iOS

```bash
cd ios/Invelio
xcodegen generate
open Invelio.xcodeproj
```

Requires Xcode 16+ and iOS 17+ deployment target. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) via `brew install xcodegen`.

## Tech Stack

- **Backend:** Python 3.12, FastAPI, LangGraph, OpenAI/Gemini API
- **iOS:** SwiftUI (iOS 17+), Swift Charts, Swift Concurrency
- **Data:** Sectors REST API + Sectors MCP
- **Database:** PostgreSQL via Supabase
- **Caching:** In-memory + PostgreSQL (two-layer, TTL-based)
- **CI:** GitHub Actions (ruff + pytest, xcodebuild)

## Key Constraints

- **1,000 Sectors API credits** — use mock data during development, cache aggressively in production
- **17-day timeline** — ship simple first, iterate
- **Sectors is the core** — removing Sectors data must break the app's functionality
