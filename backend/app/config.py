from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    sectors_api_key: str = ""
    anthropic_api_key: str = ""
    database_url: str = "sqlite+aiosqlite:///./invelio.db"
    environment: str = "development"
    log_level: str = "info"
    cors_origins: list[str] = ["*"]

    sectors_base_url: str = "https://api.sectors.app/v1"
    sectors_cache_ttl_prices: int = 300
    sectors_cache_ttl_fundamentals: int = 86400

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
