# Invelio API Contract

Base URL (local): `http://localhost:8000/api`. Interactive docs: `http://localhost:8000/docs`.

All prices are in IDR. `*_pct` fields are percentages (`-0.79` means -0.79%). Nullable fields are marked `| null`.
While `USE_MOCK_DATA=true`, responses come from bundled sample data in the same shape (the backend still needs its database for the cache).

Tracked tickers: BBCA, BBRI, BMRI, BBNI, TLKM, ASII, UNVR, ICBP, AMRT, ANTM.

## GET /stocks

Home screen stock list.

```json
{
  "stocks": [
    {
      "ticker": "BBCA",
      "name": "PT Bank Central Asia Tbk.",
      "sector": "Financials",
      "sub_sector": "Banks",
      "price": 6300.0,
      "change_pct": -0.79,
      "market_cap": 768866486850000.0
    }
  ]
}
```

## GET /stock/{ticker}

Stock detail. `ticker` is case-insensitive. Returns 404 for tickers outside the tracked list.
`prices` covers roughly the last 90 days, oldest first. `der` is null for banks.

```json
{
  "ticker": "TLKM",
  "name": "PT Telkom Indonesia (Persero) Tbk",
  "sector": "Infrastructures",
  "sub_sector": "Telecommunication",
  "price": 2560.0,
  "change_pct": -1.16,
  "market_cap": 253599274496000.0,
  "fundamentals": {
    "pe": 14.52,
    "pb": 2.14,
    "roe_pct": 12.95,
    "der": 0.42,
    "dividend_yield_pct": 8.72
  },
  "week52_high": 3990.0,
  "week52_low": 2350.0,
  "prices": [
    {"date": "2026-09-18", "open": 2525.0, "high": 2575.0, "low": 2475.0, "close": 2560.0, "volume": 282216877}
  ]
}
```

Types: `fundamentals.*` are `number | null`; `prices[].open/high/low/volume` are `number | null`.

## GET /market-overview

Home screen market header.

```json
{
  "ihsg": {
    "name": "IHSG",
    "value": 7050.0,
    "change_pct": -0.34,
    "date": "2026-09-18",
    "series": [{"date": "2026-09-18", "value": 7050.0}]
  },
  "foreign_flow": {"date": "2026-09-18", "net_foreign_inflow": 408315476846.0},
  "top_gainers": [{"ticker": "ANTM", "name": "Aneka Tambang Tbk.", "price": 3340.0, "change_pct": 1.98}],
  "top_losers": [{"ticker": "BBNI", "name": "PT Bank Negara Indonesia (Persero) Tbk", "price": 3650.0, "change_pct": -2.67}],
  "most_traded": [{"ticker": "TLKM", "name": "PT Telkom Indonesia (Persero) Tbk", "volume": 282216877, "price": 2560.0}]
}
```

`foreign_flow` can be null. `net_foreign_inflow` is IDR, positive means foreign investors were net buyers.
`top_gainers` and `top_losers` are market-wide and can include tickers outside the tracked list.

## GET /recommendations

AI stock scores from the Scoring Agent, best first. Empty list until the first scoring run.
Each component is 0-100 (higher is better; a high `risk` score means low risk).
`overall_score` weights: fundamental 30%, macro 15%, sector 20%, risk 15%, sentiment 20%.

```json
{
  "scored_at": "2026-09-22T03:15:00Z",
  "recommendations": [
    {
      "ticker": "BMRI",
      "name": "PT Bank Mandiri (Persero) Tbk",
      "overall_score": 70.5,
      "recommendation": "BUY",
      "reasoning": "BMRI presents a strong overall score of 70.5 supported by an excellent fundamental score of 97.6 ...",
      "scores": {"fundamental": 97.6, "macro": 40.8, "sector": 70.2, "risk": 74.0, "sentiment": 50.0},
      "scored_at": "2026-09-22T03:15:00Z"
    }
  ]
}
```

`recommendation` is one of `BUY`, `HOLD`, `SELL`. `scored_at` is UTC.

## POST /scoring/run

Runs the Scoring Agent and returns the same shape as `GET /recommendations`. If the last run is
less than an hour old it returns the stored results instead of running again. Takes a few seconds.

## GET /alerts

Alerts from the Alert Agent, newest first. Send the device id in the `X-Device-Id` header (the same
`device_id` stored in `user_installations`). Market-wide alerts (no device) are returned to every
device; device-specific alerts only to their owner. Without the header, only market-wide alerts.

Query params: `unread_only` (default `false`), `limit` (default 50, max 200).

```json
{
  "unread_count": 2,
  "alerts": [
    {
      "id": 1,
      "ticker": "BBCA",
      "alert_type": "price_spike",
      "severity": "high",
      "message": "BBCA jumped 6%",
      "is_read": false,
      "created_at": "2026-09-22T03:00:00Z"
    }
  ]
}
```

`alert_type`: `price_spike`, `volume_surge`, `sentiment_shift`. `severity`: `high`, `medium`, `low`.

## POST /alerts/{id}/read

Marks one alert as read and returns it (same shape as one item above). Send `X-Device-Id`.
Returns 404 if the alert does not exist or belongs to another device.

## Errors

- `404` `{"detail": "..."}`: unknown or untracked ticker.
- `502` `{"detail": "Market data unavailable", "upstream_status": 429}`: the market data provider failed.
