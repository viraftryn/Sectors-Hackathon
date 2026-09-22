from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.clients.cached_sectors import CachedSectorsClient
from app.db.database import get_db


def get_sectors(db: AsyncSession = Depends(get_db)) -> CachedSectorsClient:
    return CachedSectorsClient(db)
