from collections.abc import AsyncIterator

from app.clients.cached_sectors import CachedSectorsClient
from app.clients.mock_sectors import MockSectorsClient
from app.clients.sectors import SectorsSource
from app.config import settings
from app.db.database import async_session


async def get_sectors() -> AsyncIterator[SectorsSource]:
    if settings.use_mock_sectors:
        yield MockSectorsClient()
        return
    async with async_session() as db:
        yield CachedSectorsClient(db)
