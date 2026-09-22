"""Chat endpoint — streams Chatbot Agent responses via SSE."""

from __future__ import annotations

import json
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.chatbot import ChatbotAgent
from app.config import settings
from app.models.schemas import ChatRequest, ChatResponse

logger = logging.getLogger(__name__)

router = APIRouter()


# ---------------------------------------------------------------------------
# Optional DB dependency — chatbot works without PostgreSQL
# ---------------------------------------------------------------------------


async def _get_optional_db() -> AsyncSession | None:
    try:
        from app.db.database import get_db

        gen = get_db()
        session = await anext(gen)
        await session.execute(text("SELECT 1"))
    except Exception:
        logger.debug("DB unavailable — chat runs without history persistence")
        yield None
        return
    try:
        yield session
    finally:
        await gen.aclose()


async def _load_history(
    db: AsyncSession | None, session_id: uuid.UUID
) -> list[dict[str, str]]:
    if db is None:
        return []
    try:
        result = await db.execute(
            text(
                "SELECT role, content FROM chat_history "
                "WHERE session_id = :sid ORDER BY created_at DESC LIMIT 20"
            ),
            {"sid": str(session_id)},
        )
        rows = result.fetchall()
        return [{"role": r.role, "content": r.content} for r in reversed(rows)]
    except Exception:
        logger.debug("Could not load chat history")
        return []


async def _save_message(
    db: AsyncSession | None,
    session_id: uuid.UUID,
    role: str,
    content: str,
) -> None:
    if db is None:
        return
    try:
        await db.execute(
            text(
                "INSERT INTO chat_history (session_id, role, content) "
                "VALUES (:sid, :role, :content)"
            ),
            {"sid": str(session_id), "role": role, "content": content},
        )
        await db.commit()
    except Exception:
        logger.debug("Could not save chat message")


def _require_llm_key() -> None:
    if settings.chatbot_provider == "gemini" and not settings.gemini_api_key:
        raise HTTPException(
            status_code=503,
            detail="Gemini API key not configured — set GEMINI_API_KEY in .env",
        )
    if settings.chatbot_provider != "gemini" and not settings.openai_api_key:
        raise HTTPException(
            status_code=503,
            detail="OpenAI API key not configured — set OPENAI_API_KEY in .env",
        )


@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    db: AsyncSession | None = Depends(_get_optional_db),
):
    """Send a message and receive a complete JSON response."""
    _require_llm_key()
    agent = ChatbotAgent(db)
    history = await _load_history(db, request.session_id)
    await _save_message(db, request.session_id, "user", request.message)

    try:
        response_text = await agent.run(request.message, history)
    except Exception as exc:
        logger.error("Chatbot agent error: %s", exc)
        msg = str(exc)
        if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
            raise HTTPException(
                status_code=429,
                detail="LLM rate limit exceeded — retry shortly",
            ) from exc
        raise HTTPException(
            status_code=502, detail="LLM service error"
        ) from exc
    await _save_message(db, request.session_id, "assistant", response_text)

    return ChatResponse(session_id=request.session_id, response=response_text)


@router.post("/chat/stream")
async def chat_stream(
    request: ChatRequest,
    db: AsyncSession | None = Depends(_get_optional_db),
):
    """Send a message and receive a streaming SSE response."""
    _require_llm_key()
    agent = ChatbotAgent(db)
    history = await _load_history(db, request.session_id)
    await _save_message(db, request.session_id, "user", request.message)

    async def event_generator():
        full_response: list[str] = []
        try:
            async for chunk in agent.stream(request.message, history):
                full_response.append(chunk)
                yield f"data: {json.dumps({'content': chunk})}\n\n"
        except Exception as exc:
            logger.error("Chatbot stream error: %s", exc)
            yield f"data: {json.dumps({'error': str(exc)})}\n\n"

        response_text = "".join(full_response)
        await _save_message(db, request.session_id, "assistant", response_text)
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
