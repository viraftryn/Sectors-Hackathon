import httpx
import pytest

from app.clients.sectors import SectorsClient, SectorsError, bare_symbol, screener_where


@pytest.fixture(autouse=True)
def _clear_last_good() -> None:
    SectorsClient._last_good.clear()


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
    await client.get_daily_prices("bbca.jk")

    assert seen[0].url.path == "/v2/daily/BBCA/"
    assert "start" in seen[0].url.params
    assert "Authorization" in seen[0].headers


async def test_top_companies_limits_credit_cost() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={})

    await SectorsClient(transport=httpx.MockTransport(handler)).get_top_companies()
    assert seen[0].url.params["periods"] == "1d"


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


async def test_serves_last_good_response_when_api_fails() -> None:
    responses = iter([httpx.Response(200, json=[{"close": 1}]), httpx.Response(503)])
    client = SectorsClient(transport=httpx.MockTransport(lambda r: next(responses)))

    first = await client.get_daily_prices("BBCA")
    second = await client.get_daily_prices("BBCA")

    assert first == second == [{"close": 1}]


async def test_network_error_without_history_raises_503() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("offline")

    with pytest.raises(SectorsError) as exc:
        await SectorsClient(transport=httpx.MockTransport(handler)).get_ihsg()
    assert exc.value.status_code == 503


async def test_not_found_is_never_masked() -> None:
    responses = iter([httpx.Response(200, json={}), httpx.Response(404)])
    client = SectorsClient(transport=httpx.MockTransport(lambda r: next(responses)))
    await client.get_company_report("BBCA")
    with pytest.raises(SectorsError):
        await client.get_company_report("BBCA")
