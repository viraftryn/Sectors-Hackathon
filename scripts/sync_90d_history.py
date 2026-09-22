"""
Sync 90-day daily price history from Sectors API v2 to Supabase PostgreSQL.
Runs for 10 core stocks: BBCA, BBRI, BMRI, BBNI, TLKM, ASII, UNVR, ICBP, AMRT, ANTM.
"""

import httpx
from datetime import date, timedelta

SECTORS_KEY = "e94f68c02c4d6d8539dcb6748464c9a2f41a9fa9f6b41ae9e1e5aa5562902e2c"
SUPABASE_URL = "https://zvtuvfamsbwgeawnkwpp.supabase.co"
SUPABASE_KEY = "sb_publishable_jyOUKXnYdcLVHgGRpp7zCg_wMFxl9vW"

CORE_TICKERS = [
    "BBCA", "BBRI", "BMRI", "BBNI", "TLKM",
    "ASII", "UNVR", "ICBP", "AMRT", "ANTM"
]

sectors_headers = {"Authorization": SECTORS_KEY}
supabase_headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates"
}

def sync_ticker_90d(ticker: str, start_date: str):
    print(f"\n--- Syncing 90-day daily history for {ticker} (since {start_date}) ---")
    url = f"https://api.sectors.app/v2/daily/{ticker}/?start={start_date}"
    try:
        res = httpx.get(url, headers=sectors_headers, timeout=25.0)
        if res.status_code != 200:
            print(f"❌ Sectors API error HTTP {res.status_code}: {res.text[:100]}")
            return
        
        items = res.json()
        if not isinstance(items, list) or not items:
            print(f"⚠️ No price items returned for {ticker}")
            return
        
        print(f"📦 Received {len(items)} trading days ({items[0]['date']} -> {items[-1]['date']})")
        
        payload = []
        for p in items:
            payload.append({
                "ticker": ticker,
                "date": p["date"],
                "open": p.get("open"),
                "high": p.get("high"),
                "low": p.get("low"),
                "close": p["close"],
                "volume": p.get("volume"),
            })
        
        # Post to Supabase REST /rest/v1/stock_daily_prices
        sb_url = f"{SUPABASE_URL}/rest/v1/stock_daily_prices"
        up_res = httpx.post(sb_url, headers=supabase_headers, json=payload, timeout=30.0)
        print(f"✅ Supabase stock_daily_prices upsert HTTP {up_res.status_code}: {len(payload)} rows stored")

    except Exception as e:
        print(f"❌ Error syncing {ticker}: {e}")

def main():
    today = date(2026, 9, 22)
    start_90d = (today - timedelta(days=90)).strftime("%Y-%m-%d")
    print("=" * 65)
    print(f"SYNCING 90-DAY PRICE HISTORY (Start: {start_90d})")
    print("=" * 65)
    for ticker in CORE_TICKERS:
        sync_ticker_90d(ticker, start_90d)
    print("\n🎉 ALL 10 STOCKS 90-DAY HISTORY SYNC COMPLETED!")

if __name__ == "__main__":
    main()
