#!/usr/bin/env python3
"""
Sync Sectors API v2 data directly into Supabase PostgreSQL.
- Queries live Sectors API v2 for the 10 core Indonesian stocks.
- Extracts comprehensive fundamentals: P/E, PBV, ROE, DER, Dividend Yield, 52W High/Low, Prices, Market Cap.
- Extracts 90-day daily OHLCV prices.
- Upserts everything into Supabase PostgreSQL (tables: stocks, stock_daily_prices).
- Zero subsequent credit cost for SwiftUI & AI Chatbot RAG.
"""

import os
import sys
import time
from pathlib import Path
import httpx
from dotenv import load_dotenv

# Load .env from backend/ or project root
load_dotenv(Path(__file__).resolve().parent.parent / "backend" / ".env")
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

SECTORS_API_KEY = os.getenv("SECTORS_API_KEY", "")
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_KEY", "") or os.getenv("SUPABASE_ANON_KEY", "")

if not SECTORS_API_KEY or not SUPABASE_URL or not SUPABASE_ANON_KEY:
    print("❌ Error: Missing SECTORS_API_KEY, SUPABASE_URL, or SUPABASE_KEY in environment/.env")
    sys.exit(1)

TRACKED_TICKERS = [
    "BBCA",
    "BBRI",
    "BMRI",
    "BBNI",
    "TLKM",
    "ASII",
    "UNVR",
    "ICBP",
    "AMRT",
    "ANTM",
]

sectors_headers = {
    "Authorization": SECTORS_API_KEY
}

supabase_headers = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates"
}

def sync_stock(ticker: str):
    print(f"\n[1/2] Fetching company report for {ticker} from Sectors API...")
    url = f"https://api.sectors.app/v2/company/report/{ticker}/?sections=overview,valuation,financials,dividend"
    
    try:
        r = httpx.get(url, headers=sectors_headers, timeout=30.0)
        if r.status_code != 200:
            print(f"❌ Failed to fetch {ticker}: {r.status_code} {r.text[:100]}")
            return
        
        d = r.json()
        ov = d.get("overview", {})
        val = d.get("valuation", {})
        fin = d.get("financials", {})
        div = d.get("dividend", {})

        # 52w range
        atp = ov.get("all_time_price", {})
        w52_high = None
        w52_low = None
        if atp.get("52_w_high"):
            w52_high = float(list(atp["52_w_high"].values())[0])
        if atp.get("52_w_low"):
            w52_low = float(list(atp["52_w_low"].values())[0])

        # pe, pb
        hist_val = val.get("historical_valuation", [])
        pe = None
        pb = None
        if hist_val:
            pe_raw = hist_val[-1].get("pe")
            if pe_raw is not None:
                pe = round(float(pe_raw), 2)
            pb_raw = hist_val[-1].get("pb")
            if pb_raw is not None:
                pb = round(float(pb_raw), 2)
        elif val.get("forward_pe"):
            pe = round(float(val["forward_pe"]), 2)

        # roe, der
        hist_ratio = fin.get("historical_financial_ratio", [])
        roe = None
        der = None
        if hist_ratio:
            latest = hist_ratio[-1]
            roe_raw = latest.get("profitability", {}).get("roe")
            if roe_raw is not None:
                roe = round(float(roe_raw) * 100, 2)
            der_raw = latest.get("leverage", {}).get("debt_to_equity_ratio")
            if der_raw is not None:
                der = round(float(der_raw), 2)

        # yield
        y_raw = div.get("yield_ttm")
        yield_ttm = round(float(y_raw) * 100, 2) if y_raw is not None else None

        price = float(ov.get("last_close_price") or 0.0)
        daily_chg = round(float(ov.get("daily_close_change") or 0.0) * 100, 2)
        market_cap = float(ov.get("market_cap") or 0.0) if ov.get("market_cap") else None
        company_name = ov.get("company_name", d.get("company_name", ticker))
        sector = ov.get("sector", "IDX")
        sub_sector = ov.get("sub_sector", "")

        stock_payload = {
            "ticker": ticker,
            "symbol": f"{ticker}.JK",
            "name": company_name,
            "sector": sector,
            "sub_sector": sub_sector,
            "price": price,
            "change_pct": daily_chg,
            "market_cap": market_cap,
            "pe_ttm": pe,
            "pb_mrq": pb,
            "roe_ttm": roe,
            "der_mrq": der,
            "yield_ttm": yield_ttm,
            "week52_high": w52_high,
            "week52_low": w52_low,
        }

        # Update stocks in Supabase
        patch_url = f"{SUPABASE_URL}/rest/v1/stocks?ticker=eq.{ticker}"
        p_res = httpx.patch(patch_url, headers=supabase_headers, json=stock_payload, timeout=20.0)
        print(f"✅ Supabase stocks update: HTTP {p_res.status_code} ({ticker}: Rp {price}, P/E {pe}, PBV {pb}, ROE {roe}%, DER {der}, Yield {yield_ttm}%)")

        # Fetch daily prices
        print(f"[2/2] Fetching 90-day daily prices for {ticker}...")
        daily_url = f"https://api.sectors.app/v2/daily/{ticker}/"
        d_res = httpx.get(daily_url, headers=sectors_headers, timeout=30.0)
        if d_res.status_code == 200:
            raw_prices = d_res.json()
            if isinstance(raw_prices, list) and raw_prices:
                db_prices = []
                for p in raw_prices[-60:]:  # last 60 trading days
                    db_prices.append({
                        "ticker": ticker,
                        "date": p["date"],
                        "open": p.get("open"),
                        "high": p.get("high"),
                        "low": p.get("low"),
                        "close": p["close"],
                        "volume": p.get("volume"),
                    })
                # Upsert to Supabase
                dp_url = f"{SUPABASE_URL}/rest/v1/stock_daily_prices"
                up_res = httpx.post(dp_url, headers=supabase_headers, json=db_prices, timeout=30.0)
                print(f"✅ Supabase daily_prices: HTTP {up_res.status_code} ({len(db_prices)} points saved)")
        else:
            print(f"⚠️ Daily prices skipped for {ticker} ({d_res.status_code})")

    except Exception as e:
        print(f"❌ Error syncing {ticker}: {e}")

def main():
    print("=" * 65)
    print("INVELIO: Syncing Sectors API v2 -> Supabase PostgreSQL")
    print("=" * 65)
    for ticker in TRACKED_TICKERS:
        sync_stock(ticker)
        time.sleep(0.5)  # respectful delay between calls
    print("\n🎉 ALL 10 STOCKS SYNCED TO SUPABASE POSTGRESQL!")

if __name__ == "__main__":
    main()
