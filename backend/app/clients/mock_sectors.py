"""Offline stand-in for SectorsClient, served from app/mock_data/v2 (Sectors v2 response shapes)."""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

from app.clients.sectors import SUBSECTOR_SECTIONS, SectorsError, bare_symbol

MOCK_DIR = Path(__file__).resolve().parent.parent / "mock_data" / "v2"
DEFAULT_WINDOW = 22
MAX_WINDOW = 63


@cache
def _load(name: str) -> Any:
    path = MOCK_DIR / f"{name}.json"
    if not path.exists():
        raise SectorsError(404, f"No mock data for {name}")
    return json.loads(path.read_text())


def _window(rows: list[dict[str, Any]], start: str | None, end: str | None) -> list[dict[str, Any]]:
    if end:
        rows = [r for r in rows if r["date"] <= end]
    if start:
        rows = [r for r in rows if r["date"] >= start]
        return rows[-MAX_WINDOW:]
    return rows[-DEFAULT_WINDOW:]


def _page(items: list[dict[str, Any]], limit: int) -> dict[str, Any]:
    page = items[:limit]
    return {
        "results": page,
        "pagination": {
            "total_count": len(items),
            "showing": len(page),
            "limit": limit,
            "offset": 0,
            "has_next": len(items) > limit,
            "has_previous": False,
            "next_offset": limit if len(items) > limit else None,
            "previous_offset": None,
        },
    }


class MockSectorsClient:
    async def screen_companies(self, symbols: list[str]) -> dict[str, Any]:
        wanted = {f"{bare_symbol(s)}.JK" for s in symbols}
        rows = [r for r in _load("companies_screener")["results"] if r["symbol"] in wanted]
        return _page(rows, len(symbols))

    async def get_daily(
        self, symbol: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        return _window(_load(f"daily_{bare_symbol(symbol)}"), start, end)

    async def get_index_daily(
        self, index_code: str, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        return _window(_load(f"index_daily_{index_code.lower()}"), start, end)

    async def get_subsector_report(self, sub_sector: str) -> dict[str, Any]:
        report: dict[str, Any] = _load(f"subsector_report_{sub_sector}")
        keep = {"sector", "sub_sector", *SUBSECTOR_SECTIONS}
        return {k: v for k, v in report.items() if k in keep}

    async def get_top_changes(self, period: str = "1d", n_stock: int = 5) -> dict[str, Any]:
        data = _load("top_changes")
        return {
            "top_gainers": {period: data["top_gainers"][period][:n_stock]},
            "top_losers": {period: data["top_losers"][period][:n_stock]},
        }

    async def get_most_traded(self, n_stock: int = 5) -> dict[str, Any]:
        return {day: rows[:n_stock] for day, rows in _load("most_traded").items()}

    async def get_news(
        self, symbols: list[str] | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]:
        items: list[dict[str, Any]] = _load("news")
        if symbols:
            wanted = {f"{bare_symbol(s)}.JK" for s in symbols}
            items = [a for a in items if wanted & set(a["symbols"])]
        if start:
            items = [a for a in items if a["timestamp"] >= start]
        return _page(items, limit)

    async def get_filings(
        self, symbol: str | None = None, limit: int = 20, start: str | None = None
    ) -> dict[str, Any]:
        items: list[dict[str, Any]] = _load("filings")
        if symbol:
            items = [f for f in items if f["symbol"] == f"{bare_symbol(symbol)}.JK"]
        if start:
            items = [f for f in items if f["timestamp"] >= start]
        return _page(items, limit)

    async def get_foreign_flow(
        self, symbol: str = "IHSG", start: str | None = None, end: str | None = None
    ) -> dict[str, Any]:
        flow = dict(_load(f"foreign_flow_{bare_symbol(symbol)}"))
        flow["data"] = _window(flow["data"], start, end)
        return flow
