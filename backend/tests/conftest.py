import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def _never_call_real_sectors(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "use_mock_sectors", True)
