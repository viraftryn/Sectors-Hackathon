from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    sectors_api_key: str = ""
    openai_api_key: str = ""
    gemini_api_key: str = ""
    database_url: str = "postgresql+asyncpg://postgres:password@localhost:5432/invelio"
    supabase_url: str = ""
    supabase_key: str = ""
    environment: str = "development"
    log_level: str = "info"
    cors_origins: list[str] = ["*"]

    sectors_base_url: str = "https://api.sectors.app/v2"
    use_mock_sectors: bool = True
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

    # Cache TTLs (seconds) — matches implementation plan Section 5.2
    cache_ttl_prices: int = 300  # 5 min — /daily, /most-traded, /top-companies
    cache_ttl_market_index: int = 600  # 10 min — /idx-total
    cache_ttl_news: int = 900  # 15 min — /news
    cache_ttl_sector_reports: int = 3600  # 1 hour — /sector/report, /news/filings
    cache_ttl_fundamentals: int = 86400  # 24 hours — /companies/report, /companies

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
