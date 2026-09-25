"""Background alert scanner — runs every N minutes during IDX market hours.

IDX trading sessions: 09:00–16:00 WIB (UTC+7).
The scheduler fires every `alert_scan_interval_minutes` but skips execution
outside the configured market-hours window.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.config import settings

logger = logging.getLogger(__name__)

WIB = timezone(timedelta(hours=7))

scheduler = AsyncIOScheduler()


async def _run_alert_scan() -> None:
    now_wib = datetime.now(WIB)
    hour = now_wib.hour
    weekday = now_wib.weekday()  # 0=Mon … 6=Sun

    if weekday >= 5:
        logger.debug("Skipping alert scan — weekend (WIB: %s)", now_wib)
        return
    if hour < settings.alert_scan_market_open_hour or hour >= settings.alert_scan_market_close_hour:
        logger.debug("Skipping alert scan — outside market hours (WIB: %s)", now_wib)
        return

    logger.info("Scheduled alert scan starting (WIB: %s)", now_wib)

    from app.db.database import get_session_factory

    async with get_session_factory()() as db:
        from app.agents.alert import AlertAgent

        agent = AlertAgent(db)
        try:
            result = await agent.run()
            logger.info("Scheduled scan result: %s", result)
        except Exception:
            logger.exception("Scheduled alert scan failed")


def start_scheduler() -> None:
    scheduler.add_job(
        _run_alert_scan,
        "interval",
        minutes=settings.alert_scan_interval_minutes,
        id="alert_scan",
        replace_existing=True,
    )
    scheduler.start()
    logger.info(
        "Alert scheduler started — every %d min, market hours %02d:00–%02d:00 WIB",
        settings.alert_scan_interval_minutes,
        settings.alert_scan_market_open_hour,
        settings.alert_scan_market_close_hour,
    )


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Alert scheduler stopped")
