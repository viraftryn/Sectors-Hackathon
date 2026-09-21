"""Mock Sectors API responses for development — zero credits spent.

Switch to real API only for integration testing and demo day.

Each file in ``sectors/`` is one Sectors v2 response, named after the cache key the
CachedSectorsClient uses (":" is written as "__", e.g. ``daily_prices__BBCA.json``).
To add a fixture, drop a new file there. ``companies_list.json`` is a real screener
response; prices, news, filings and flows are synthetic data in the real v2 shapes.
"""

import json
from copy import deepcopy
from pathlib import Path
from typing import Any

# A Sectors JSON response is either a single object or a list of objects.
JsonData = dict[str, Any] | list[dict[str, Any]]

FIXTURES_DIR = Path(__file__).resolve().parent / "sectors"

MOCK_RESPONSES: dict[str, JsonData] = {
    path.stem.replace("__", ":"): json.loads(path.read_text())
    for path in sorted(FIXTURES_DIR.glob("*.json"))
}


class MockDataMissingError(LookupError):
    """Raised when mock mode is on but no fixture exists for the requested cache key."""


def get_mock_response(cache_key: str) -> JsonData:
    """Return a deep copy of the mock fixture for a cache key.

    Keyed by the same cache keys the CachedSectorsClient uses (e.g. "company_report:BBCA").
    A deep copy is returned so callers can mutate the result without corrupting the shared
    fixture (or an L1-cached reference). Raises MockDataMissingError with a helpful message
    when no fixture is registered, so devs know to add one instead of getting silent bad data.
    """
    if cache_key not in MOCK_RESPONSES:
        available = ", ".join(sorted(MOCK_RESPONSES)) or "(none)"
        filename = cache_key.replace(":", "__") + ".json"
        raise MockDataMissingError(
            f"No mock fixture for cache key {cache_key!r}. "
            f"Add app/mock_data/sectors/{filename}. Available keys: {available}"
        )
    return deepcopy(MOCK_RESPONSES[cache_key])
