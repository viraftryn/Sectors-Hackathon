from collections.abc import Iterator
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.database import get_db
from app.main import app
from tests.conftest import make_sqlite_engine

# Mirrors the alerts table in supabase/migrations/*_invelio_schema.sql.
ALERTS_DDL = """CREATE TABLE alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT, device_id VARCHAR(64), ticker VARCHAR(10),
    alert_type VARCHAR(50) NOT NULL, severity VARCHAR(20) NOT NULL DEFAULT 'medium',
    message TEXT NOT NULL, is_read BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMP NOT NULL)"""

NOW = datetime(2026, 9, 22, 3, 0, tzinfo=UTC)
SEED = [
    (None, "BBCA", "price_spike", "high", "BBCA jumped 6%", NOW),
    (
        "device-a",
        "TLKM",
        "sentiment_shift",
        "medium",
        "TLKM news turned bearish",
        NOW - timedelta(hours=1),
    ),
    ("device-b", "ASII", "volume_surge", "low", "ASII volume doubled", NOW - timedelta(hours=2)),
]


@pytest.fixture
def client() -> Iterator[TestClient]:
    engine = make_sqlite_engine()
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    ready = False

    async def _sqlite_db():  # type: ignore[no-untyped-def]
        nonlocal ready
        async with factory() as session:
            if not ready:
                await session.execute(text(ALERTS_DDL))
                for device, ticker, kind, severity, message, created in SEED:
                    await session.execute(
                        text(
                            "INSERT INTO alerts (device_id, ticker, alert_type, severity, message, "
                            "created_at) VALUES (:d, :t, :k, :s, :m, :c)"
                        ),
                        {
                            "d": device,
                            "t": ticker,
                            "k": kind,
                            "s": severity,
                            "m": message,
                            "c": created,
                        },
                    )
                await session.commit()
                ready = True
            yield session

    app.dependency_overrides[get_db] = _sqlite_db
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_db, None)


def test_device_sees_market_and_own_alerts(client: TestClient) -> None:
    body = client.get("/api/alerts", headers={"X-Device-Id": "device-a"}).json()
    assert [a["ticker"] for a in body["alerts"]] == ["BBCA", "TLKM"]
    assert body["unread_count"] == 2
    assert body["alerts"][0]["created_at"] == "2026-09-22T03:00:00Z"


def test_without_device_only_market_alerts(client: TestClient) -> None:
    body = client.get("/api/alerts").json()
    assert [a["ticker"] for a in body["alerts"]] == ["BBCA"]


def test_mark_read_updates_unread_count(client: TestClient) -> None:
    headers = {"X-Device-Id": "device-a"}
    alert_id = client.get("/api/alerts", headers=headers).json()["alerts"][0]["id"]
    marked = client.post(f"/api/alerts/{alert_id}/read", headers=headers)
    assert marked.status_code == 200 and marked.json()["is_read"] is True
    body = client.get("/api/alerts?unread_only=true", headers=headers).json()
    assert body["unread_count"] == 1
    assert [a["ticker"] for a in body["alerts"]] == ["TLKM"]


def test_cannot_mark_another_devices_alert(client: TestClient) -> None:
    others = client.get("/api/alerts", headers={"X-Device-Id": "device-b"}).json()["alerts"]
    asii_id = next(a["id"] for a in others if a["ticker"] == "ASII")
    assert (
        client.post(f"/api/alerts/{asii_id}/read", headers={"X-Device-Id": "device-a"}).status_code
        == 404
    )


def test_timestamps_are_valid_iso_utc(client: TestClient) -> None:
    from datetime import datetime

    created = client.get("/api/alerts").json()["alerts"][0]["created_at"]
    assert created.endswith("Z") and "+" not in created
    datetime.fromisoformat(created.replace("Z", "+00:00"))


def test_mark_read_accepts_patch(client: TestClient) -> None:
    headers = {"X-Device-Id": "device-a"}
    alert_id = client.get("/api/alerts", headers=headers).json()["alerts"][0]["id"]
    assert client.patch(f"/api/alerts/{alert_id}/read", headers=headers).json()["is_read"] is True
