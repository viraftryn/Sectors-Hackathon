from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    sectors_api_key: str = ""
    openai_api_key: str = ""
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.5-flash-lite"
    database_url: str = "postgresql+asyncpg://postgres:password@localhost:5432/invelio"
    supabase_url: str = ""
    supabase_key: str = ""
    environment: str = "development"
    log_level: str = "info"
    cors_origins: list[str] = ["*"]

    sectors_base_url: str = "https://api.sectors.app/v2"
    scoring_min_interval_seconds: int = 3600
    tracked_tickers: list[str] = [
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

    chatbot_model: str = "gemini-3.5-flash-lite"
    chatbot_provider: str = "gemini"
    sectors_mcp_url: str = "https://sectors-mcp.supertype.ai/mcp"

    # MCP vs REST toggle: True = live Sectors MCP (demo), False = REST + cache (development).
    use_mcp: bool = False

    # Zero-credit development mode: serve saved fixtures instead of calling the Sectors API.
    # Defaults ON so we never burn credits by accident (plan Section 5.4). Set to false for
    # integration testing and demo day.
    use_mock_data: bool = True

    # Alert scheduler
    alert_scan_interval_minutes: int = 30
    alert_scan_market_open_hour: int = 9   # WIB (UTC+7)
    alert_scan_market_close_hour: int = 16  # 16 WIB = covers post-close settlement

    # Cache TTLs (seconds) — matches implementation plan Section 5.2
    cache_ttl_prices: int = 300  # 5 min — /daily, /most-traded, /top-companies
    cache_ttl_market_index: int = 600  # 10 min — /idx-total
    cache_ttl_news: int = 900  # 15 min — /news
    cache_ttl_sector_reports: int = 3600  # 1 hour — /sector/report, /news/filings
    cache_ttl_fundamentals: int = 86400  # 24 hours — /companies/report, /companies

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
