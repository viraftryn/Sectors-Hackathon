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

echo "🚀 Starting Invelio FastAPI Backend..."
echo "📍 Local Address: http://127.0.0.1:8000"
echo "📚 API Docs:      http://127.0.0.1:8000/docs"
echo "🌐 Network Host:  0.0.0.0:8000 (accessible by iOS simulator/device)"
echo "------------------------------------------------------------"

# Start uvicorn server with auto-reload
exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
