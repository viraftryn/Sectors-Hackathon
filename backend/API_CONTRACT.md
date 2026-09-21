# Invelio API Contract

Base URL (local): `http://localhost:8000/api`. Interactive docs: `http://localhost:8000/docs`.

All prices are in IDR. `*_pct` fields are percentages (`-0.79` means -0.79%). Nullable fields are marked `| null`.
While `USE_MOCK_SECTORS=true`, responses come from bundled sample data in the same shape.

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

## Errors

- `404` `{"detail": "..."}`: unknown or untracked ticker.
- `502` `{"detail": "Market data unavailable", "upstream_status": 429}`: the market data provider failed.
