from databases import Database
from pydantic_settings import BaseSettings
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql://admin:password@localhost:5432/safewalk"
    SUPABASE_URL: str = ""
    SUPABASE_ANON_KEY: str = ""
    SUPABASE_SERVICE_KEY: str = ""
    SUPABASE_INCIDENT_TABLE: str = "incident_reports"
    SUPABASE_EMERGENCY_TABLE: str = "emergency_alerts"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

    @property
    def supabase_enabled(self) -> bool:
        return bool(
            self.SUPABASE_URL
            and (self.SUPABASE_SERVICE_KEY or self.SUPABASE_ANON_KEY)
        )

settings = Settings()


def _normalize_database_url(database_url: str) -> str:
    if not database_url.startswith(("postgresql://", "postgres://")):
        return database_url

    parts = urlsplit(database_url)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    # Supabase pooler / PgBouncer does not support asyncpg's default statement cache.
    query.setdefault("statement_cache_size", "0")
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment)
    )

# Use databases for async support
database = Database(
    _normalize_database_url(settings.DATABASE_URL),
    statement_cache_size=0,
)
