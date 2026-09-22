import json
import re
from typing import Any, AsyncGenerator

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from google import genai
from google.genai import types
from pydantic import BaseModel

from app.api.deps import get_sectors
from app.clients.cached_sectors import CachedSectorsClient
from app.clients.sectors import bare_symbol
from app.config import settings

router = APIRouter()


class ChatRequest(BaseModel):
    message: str
    session_id: str | None = None
    holdings: list[dict[str, Any]] | None = None


class ChatResponse(BaseModel):
    response: str
    ticker: str | None = None


SYSTEM_PROMPT = """You are Invelio AI, an expert Indonesian Stock Exchange (IDX / Bursa Efek Indonesia) equity research analyst.
Your mission is to provide accurate, insightful, and professional stock and portfolio analysis for Indonesian retail and institutional investors.

Guidelines:
1. Always analyze in the context of Indonesian equities (IDX).
2. Answer the user's specific question directly (e.g. why price moved, macro factors, valuation, dividend sustainability, risks, or portfolio recommendations).
3. If stock fundamental data or portfolio holdings are provided in the prompt context, use those numbers to support your analysis.
4. Format your response cleanly using Markdown with concise bullet points and bold highlights.
5. Respond in the same language as the user (English or Indonesian).
"""


async def get_stock_context(query: str, sectors: CachedSectorsClient) -> str:
    known_tickers = [
        "BBCA", "BBRI", "BMRI", "BBNI", "TLKM", "ASII", "GOTO", "AMMN", "BREN",
        "ADRO", "ICBP", "INDF", "UNVR", "KLBF", "CPIN", "SMGR", "BRPT", "PTBA",
        "ITMG", "PGAS", "MDKA", "TPIA", "MEDC", "INKP", "ANTM", "ISAT", "EXCL"
    ]
    
    upper_query = query.upper()
    detected = None
    for t in known_tickers:
        if re.search(rf"\b{t}\b", upper_query):
            detected = t
            break
            
    if not detected:
        words = re.findall(r"\b[A-Z]{4}\b", upper_query)
        if words:
            detected = words[0]

    if not detected:
        return ""

    try:
        screener = await sectors.list_companies()
        results = screener.get("results", []) if isinstance(screener, dict) else []
        row = next((r for r in results if bare_symbol(r.get("symbol", "")) == detected), None)
        if row:
            q = row.get("query_values", {})
            return (
                f"\n[Stock Context for {detected} - {row.get('company_name')}]:\n"
                f"Sector: {q.get('sector')} | Sub-sector: {q.get('sub_sector')}\n"
                f"Latest Close Price: Rp {q.get('last_close_price', 'N/A')}\n"
                f"Daily Change: {round(q.get('daily_close_change', 0) * 100, 2) if q.get('daily_close_change') is not None else 'N/A'}%\n"
                f"P/E TTM: {q.get('pe_ttm', 'N/A')}x | PBV MRQ: {q.get('pb_mrq', 'N/A')}x\n"
                f"ROE TTM: {round(q.get('roe_ttm', 0) * 100, 2) if q.get('roe_ttm') is not None else 'N/A'}%\n"
                f"Dividend Yield: {round(q.get('yield_ttm', 0) * 100, 2) if q.get('yield_ttm') is not None else 'N/A'}%\n"
                f"52-Week High/Low: Rp {q.get('52_w_high_price', 'N/A')} - Rp {q.get('52_w_low_price', 'N/A')}\n"
            )
    except Exception:
        pass
    return ""


@router.post("/chat", response_model=ChatResponse)
async def chat_endpoint(
    req: ChatRequest,
    sectors: CachedSectorsClient = Depends(get_sectors),
) -> ChatResponse:
    stock_ctx = await get_stock_context(req.message, sectors)
    prompt = req.message
    if stock_ctx:
        prompt = f"{stock_ctx}\nUser Question: {req.message}"
    if req.holdings:
        prompt = f"[User Portfolio Holdings]: {json.dumps(req.holdings)}\n" + prompt

    if not settings.gemini_api_key:
        return ChatResponse(
            response="⚠️ GEMINI_API_KEY is not configured in backend/.env. Please set a valid Gemini API key."
        )

    try:
        client = genai.Client(api_key=settings.gemini_api_key)
        response = await client.aio.models.generate_content(
            model=settings.chatbot_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                temperature=0.3,
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            ),
        )
        return ChatResponse(response=response.text or "No response generated.")
    except Exception as exc:
        return ChatResponse(response=f"⚠️ Gemini request error: {str(exc)}")


@router.post("/chat/stream")
async def chat_stream_endpoint(
    req: ChatRequest,
    sectors: CachedSectorsClient = Depends(get_sectors),
) -> StreamingResponse:
    stock_ctx = await get_stock_context(req.message, sectors)
    prompt = req.message
    if stock_ctx:
        prompt = f"{stock_ctx}\nUser Question: {req.message}"
    if req.holdings:
        prompt = f"[User Portfolio Holdings]: {json.dumps(req.holdings)}\n" + prompt

    async def event_generator() -> AsyncGenerator[str, None]:
        if not settings.gemini_api_key:
            err_data = json.dumps({"error": "GEMINI_API_KEY is not configured in backend/.env."})
            yield f"data: {err_data}\n\n"
            yield "data: [DONE]\n\n"
            return

        try:
            client = genai.Client(api_key=settings.gemini_api_key)
            response = await client.aio.models.generate_content(
                model=settings.chatbot_model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                    temperature=0.3,
                    automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
                ),
            )
            text = response.text or ""
            # Stream by sentences/paragraphs or full text for instant responsiveness
            chunk_data = json.dumps({"content": text})
            yield f"data: {chunk_data}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as exc:
            err_data = json.dumps({"error": f"AI service error: {str(exc)}"})
            yield f"data: {err_data}\n\n"
            yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
