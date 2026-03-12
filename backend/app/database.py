import os
from databases import Database
from pydantic_settings import BaseSettings


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

# Use databases for async support
database = Database(settings.DATABASE_URL)
