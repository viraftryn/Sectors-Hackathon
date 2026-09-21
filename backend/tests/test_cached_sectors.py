"""Tests for CachedSectorsClient — the credit-saving wrapper around the Sectors API."""

from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import cache_stats
from app.clients.cached_sectors import CachedSectorsClient
from app.config import settings
from app.mock_data.fixtures import MockDataMissingError, get_mock_response


class _FakeRaw:
    """Stand-in for SectorsClient that counts how many real API calls were made."""

    def __init__(self) -> None:
        self.calls = 0

    async def get_daily_prices(self, ticker: str) -> dict:
        self.calls += 1
        return {"close": 1234, "ticker": ticker}


class _ExplodingRaw:
    """Any attribute access returns a coroutine that fails — proves the API is untouched."""

    def __getattr__(self, name: str):
        async def _boom(*args: object, **kwargs: object) -> None:
            raise AssertionError(f"real Sectors API called ({name}) in mock mode")

        return _boom


async def test_second_call_is_served_from_cache(db: AsyncSession, monkeypatch) -> None:
    monkeypatch.setattr(settings, "use_mock_data", False)
    client = CachedSectorsClient(db)
    fake = _FakeRaw()
    client._raw = fake  # type: ignore[assignment]

    first = await client.get_daily_prices("BBCA")
    second = await client.get_daily_prices("BBCA")

    assert first == second == {"close": 1234, "ticker": "BBCA"}
    # The point of the whole layer: two requests, one API credit spent.
    assert fake.calls == 1
    assert cache_stats()["credits_saved"] == 1


async def test_mock_mode_returns_fixture_without_calling_api(db: AsyncSession, monkeypatch) -> None:
    monkeypatch.setattr(settings, "use_mock_data", True)
    client = CachedSectorsClient(db)
    client._raw = _ExplodingRaw()  # type: ignore[assignment]

    data = await client.get_company_report("BBCA")

    assert data["symbol"] == "BBCA.JK"
    assert data["company_name"].startswith("PT Bank Central Asia")


async def test_mock_mode_caches_the_fixture(db: AsyncSession, monkeypatch) -> None:
    monkeypatch.setattr(settings, "use_mock_data", True)
    client = CachedSectorsClient(db)
    client._raw = _ExplodingRaw()  # type: ignore[assignment]

    await client.get_idx_total()
    await client.get_idx_total()  # should be an L1 hit, not a second resolve

    assert cache_stats()["l1_hits"] == 1


async def test_mock_mode_missing_fixture_raises(db: AsyncSession, monkeypatch) -> None:
    monkeypatch.setattr(settings, "use_mock_data", True)
    client = CachedSectorsClient(db)

    with pytest.raises(MockDataMissingError):
        await client.get_daily_prices("ZZZZ")  # no fixture for daily_prices:ZZZZ


def test_get_mock_response_returns_independent_copy() -> None:
    first = get_mock_response("idx_total")
    first[0]["idx_total_market_cap"] = -999
    second = get_mock_response("idx_total")
    assert (
        second[0]["idx_total_market_cap"] != -999
    )  # mutating one copy must not corrupt the fixture
