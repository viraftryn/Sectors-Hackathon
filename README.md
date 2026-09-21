# Sectors-Hackathon Projects

Agentic AI for Indonesian Stock Analysis — powered by [Sectors API](https://sectors.app).

An iOS SwiftUI app backed by a Python agentic backend with LangGraph scoring, RAG chatbot, and real-time sentiment alerts.

## Project Structure

```
├── backend/                 # Python FastAPI backend
│   ├── app/
│   │   ├── api/routes/      # API endpoints
│   │   ├── agents/          # LangGraph AI agents (scoring, chatbot, alert)
│   │   ├── clients/         # External API clients (Sectors)
│   │   ├── db/              # Database setup & migrations
│   │   └── models/          # Pydantic schemas
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
# Edit .env with your API keys
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

- **Backend:** Python 3.12, FastAPI, LangGraph, Claude API
- **iOS:** SwiftUI, Swift Charts, Swift Concurrency
- **Data:** Sectors REST API + MCP, SQLite
- **CI:** GitHub Actions
