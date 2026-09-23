"""Gemini client (Google AI Studio). Shared by the scoring and chatbot agents."""

from __future__ import annotations

import json
from typing import Any

from google import genai
from google.genai import types

from app.config import settings


class LLMError(Exception):
    pass


async def generate_json(prompt: str, system: str, temperature: float = 0.3) -> Any:
    if not settings.gemini_api_key:
        raise LLMError("GEMINI_API_KEY is not set")
    client = genai.Client(api_key=settings.gemini_api_key)
    try:
        response = await client.aio.models.generate_content(
            model=settings.gemini_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=system,
                temperature=temperature,
                response_mime_type="application/json",
                automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            ),
        )
    except Exception as exc:
        raise LLMError(f"Gemini request failed: {exc}") from exc
    try:
        return json.loads(response.text or "")
    except json.JSONDecodeError as exc:
        raise LLMError("Gemini returned invalid JSON") from exc
