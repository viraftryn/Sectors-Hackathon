from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import _coerce_dt
from app.db.database import get_db
from app.models.schemas import Alert, AlertList, utc_iso

router = APIRouter()

VISIBLE_TO_DEVICE = "(device_id IS NULL OR device_id = :device)"


def to_alert(row: Any) -> Alert:
    return Alert(
        id=row.id,
        ticker=row.ticker,
        alert_type=row.alert_type,
        severity=row.severity,
        message=row.message,
        is_read=bool(row.is_read),
        created_at=utc_iso(_coerce_dt(row.created_at)),
    )


@router.get("/alerts", response_model=AlertList)
async def list_alerts(
    unread_only: bool = False,
    limit: int = 50,
    x_device_id: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> AlertList:
    params = {"device": x_device_id, "limit": min(limit, 200)}
    unread_filter = " AND is_read = FALSE" if unread_only else ""
    rows = await db.execute(
        text(
            "SELECT id, ticker, alert_type, severity, message, is_read, created_at FROM alerts "
            f"WHERE {VISIBLE_TO_DEVICE}{unread_filter} ORDER BY created_at DESC LIMIT :limit"
        ),
        params,
    )
    unread = await db.execute(
        text(f"SELECT COUNT(*) FROM alerts WHERE {VISIBLE_TO_DEVICE} AND is_read = FALSE"),
        params,
    )
    return AlertList(unread_count=unread.scalar_one(), alerts=[to_alert(r) for r in rows])


@router.post("/alerts/{alert_id}/read", response_model=Alert)
async def mark_alert_read(
    alert_id: int,
    x_device_id: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> Alert:
    params = {"id": alert_id, "device": x_device_id}
    await db.execute(
        text(f"UPDATE alerts SET is_read = TRUE WHERE id = :id AND {VISIBLE_TO_DEVICE}"), params
    )
    await db.commit()
    row = (
        await db.execute(
            text(
                "SELECT id, ticker, alert_type, severity, message, is_read, created_at "
                f"FROM alerts WHERE id = :id AND {VISIBLE_TO_DEVICE}"
            ),
            params,
        )
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Alert not found")
    return to_alert(row)
