import httpx
import pytest

from app.clients.mock_sectors import MockSectorsClient
from app.clients.sectors import SectorsClient, SectorsError, bare_symbol, screener_where
from app.config import settings


def test_bare_symbol() -> None:
    assert bare_symbol("bbca.jk") == "BBCA"
    assert bare_symbol("TLKM") == "TLKM"


def test_screener_where_uses_jk_suffix() -> None:
    where = screener_where(["BBCA", "tlkm"])
    assert "symbol in ['BBCA.JK','TLKM.JK']" in where
    assert "roe_ttm > -1000000" in where


async def test_real_client_builds_v2_request() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[])

    client = SectorsClient(transport=httpx.MockTransport(handler))
    await client.get_daily("bbca.jk", start="2026-09-01")

    assert str(seen[0].url) == "https://api.sectors.app/v2/daily/BBCA/?start=2026-09-01"
    assert "Authorization" in seen[0].headers


async def test_real_client_retries_once_on_429() -> None:
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(429, headers={"Retry-After": "0"})
        return httpx.Response(200, json={"data": []})

    client = SectorsClient(transport=httpx.MockTransport(handler))
    assert await client.get_foreign_flow() == {"data": []}
    assert calls == 2


async def test_real_client_raises_on_error() -> None:
    client = SectorsClient(transport=httpx.MockTransport(lambda r: httpx.Response(410)))
    with pytest.raises(SectorsError) as exc:
        await client.get_most_traded()
    assert exc.value.status_code == 410


async def test_mock_screener_returns_tracked_tickers() -> None:
    result = await MockSectorsClient().screen_companies(settings.tracked_tickers)
    symbols = {r["symbol"] for r in result["results"]}
    assert symbols == {f"{t}.JK" for t in settings.tracked_tickers}


async def test_mock_daily_window() -> None:
    mock = MockSectorsClient()
    default = await mock.get_daily("BBCA")
    ranged = await mock.get_daily("BBCA", start="2026-07-01", end="2026-08-31")
    assert len(default) == 22
    assert all("2026-07-01" <= r["date"] <= "2026-08-31" for r in ranged)


async def test_mock_news_filters_by_symbol() -> None:
    result = await MockSectorsClient().get_news(symbols=["BBCA"], limit=5)
    assert all("BBCA.JK" in a["symbols"] for a in result["results"])


async def test_mock_every_tracked_subsector_has_report() -> None:
    mock = MockSectorsClient()
    for slug in ["banks", "telecommunication", "multi-sector-holdings", "food-beverage"]:
        report = await mock.get_subsector_report(slug)
        assert "stability" in report


async def test_mock_missing_data_raises() -> None:
    with pytest.raises(SectorsError):
        await MockSectorsClient().get_daily("GOTO")
