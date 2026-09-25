#!/usr/bin/env bash
# Invelio Backend Server Startup Script

# Navigate to backend directory
cd "$(dirname "$0")" || exit 1

# Check and activate virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo "⚠️  .venv not found. Creating virtual environment..."
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements-dev.txt
fi

# Ensure .env file exists
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "📄 .env not found, copying from .env.example..."
        cp .env.example .env
    fi
fi

# Ensure PostgreSQL service is running if configured for localhost
if grep -q "localhost:5432" .env 2>/dev/null; then
    if command -v pg_isready &>/dev/null; then
        if ! pg_isready -q; then
            echo "🐘 PostgreSQL is not running. Starting via brew services..."
            brew services start postgresql@18 2>/dev/null || brew services start postgresql 2>/dev/null
            sleep 1
        fi
    fi
fi

echo "🚀 Starting Invelio FastAPI Backend..."
echo "📍 Local Address: http://127.0.0.1:8000"
echo "📚 API Docs:      http://127.0.0.1:8000/docs"
echo "🌐 Network Host:  0.0.0.0:8000 (accessible by iOS simulator/device)"
echo "------------------------------------------------------------"

# Start uvicorn server with auto-reload
exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
