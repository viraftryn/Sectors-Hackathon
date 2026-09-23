"""Tests for the Chatbot Agent."""

from __future__ import annotations

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.agents.chatbot import ChatbotAgent, ChatState, _truncate

# -- Unit: _truncate ---------------------------------------------------------


def test_truncate_short_string():
    assert _truncate("short") == "short"


def test_truncate_long_string():
    result = _truncate("x" * 5000, max_chars=100)
    assert len(result) < 5000
    assert result.endswith("[truncated]")


def test_truncate_exact_boundary():
    text = "a" * 4000
    assert _truncate(text) == text


# -- Unit: _classify_question ------------------------------------------------


@pytest.mark.asyncio
async def test_classify_single_stock():
    agent = ChatbotAgent()

    mock_response = MagicMock()
    mock_response.content = json.dumps({"question_type": "single_stock", "entities": ["BBCA"]})

    with patch("app.agents.chatbot._get_llm") as mock_llm:
        llm_instance = AsyncMock()
        llm_instance.ainvoke.return_value = mock_response
        mock_llm.return_value = llm_instance

        state: ChatState = {
            "user_message": "How is BBCA performing?",
            "chat_history": [],
            "question_type": "",
            "entities": [],
            "context": [],
            "response": "",
        }
        result = await agent._classify_question(state)

    assert result["question_type"] == "single_stock"
    assert "BBCA" in result["entities"]


@pytest.mark.asyncio
async def test_classify_comparison():
    agent = ChatbotAgent()

    mock_response = MagicMock()
    mock_response.content = json.dumps(
        {"question_type": "comparison", "entities": ["BBCA", "BMRI"]}
    )

    with patch("app.agents.chatbot._get_llm") as mock_llm:
        llm_instance = AsyncMock()
        llm_instance.ainvoke.return_value = mock_response
        mock_llm.return_value = llm_instance

        state: ChatState = {
            "user_message": "Compare BBCA and BMRI",
            "chat_history": [],
            "question_type": "",
            "entities": [],
            "context": [],
            "response": "",
        }
        result = await agent._classify_question(state)

    assert result["question_type"] == "comparison"
    assert result["entities"] == ["BBCA", "BMRI"]


@pytest.mark.asyncio
async def test_classify_handles_invalid_json():
    agent = ChatbotAgent()

    mock_response = MagicMock()
    mock_response.content = "not valid json at all"

    with patch("app.agents.chatbot._get_llm") as mock_llm:
        llm_instance = AsyncMock()
        llm_instance.ainvoke.return_value = mock_response
        mock_llm.return_value = llm_instance

        state: ChatState = {
            "user_message": "hello there",
            "chat_history": [],
            "question_type": "",
            "entities": [],
            "context": [],
            "response": "",
        }
        result = await agent._classify_question(state)

    assert result["question_type"] == "general"
    assert result["entities"] == []


# -- Unit: _format_context ---------------------------------------------------


def test_format_context_empty():
    agent = ChatbotAgent()
    assert agent._format_context([]) == "(no data retrieved)"


def test_format_context_with_data():
    agent = ChatbotAgent()
    ctx = [
        {"tool": "fetch-company-report", "args": {"symbol": "BBCA"}, "data": '{"pe": 20}'},
    ]
    result = agent._format_context(ctx)
    assert "fetch-company-report" in result
    assert "BBCA" in result


# -- Unit: _build_response_messages ------------------------------------------


def test_build_response_messages_includes_history():
    agent = ChatbotAgent()
    state: ChatState = {
        "user_message": "What about BBCA?",
        "chat_history": [
            {"role": "user", "content": "Hi"},
            {"role": "assistant", "content": "Hello!"},
        ],
        "question_type": "single_stock",
        "entities": ["BBCA"],
        "context": [],
        "response": "",
    }
    msgs = agent._build_response_messages(state)
    # system + 2 history + 1 user = 4
    assert len(msgs) == 4


def test_build_response_messages_limits_history():
    agent = ChatbotAgent()
    big_history = [{"role": "user", "content": f"msg{i}"} for i in range(20)]
    state: ChatState = {
        "user_message": "latest",
        "chat_history": big_history,
        "question_type": "general",
        "entities": [],
        "context": [],
        "response": "",
    }
    msgs = agent._build_response_messages(state)
    # system + 6 history (capped) + 1 user = 8
    assert len(msgs) == 8
