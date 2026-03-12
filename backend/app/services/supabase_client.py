from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

import httpx

from app.database import settings


class SupabaseClient:
    """Minimal async wrapper for Supabase PostgREST operations."""

    def __init__(self) -> None:
        self._base_url = settings.SUPABASE_URL.rstrip("/")
        self._anon_key = settings.SUPABASE_ANON_KEY
        self._service_key = settings.SUPABASE_SERVICE_KEY

    @property
    def enabled(self) -> bool:
        return settings.supabase_enabled and bool(self._base_url)

    def _headers(self, *, use_service_key: bool = True) -> Dict[str, str]:
        api_key = (
            self._service_key
            if use_service_key and self._service_key
            else self._anon_key
        )
        if not api_key:
            raise RuntimeError("Supabase API key is not configured.")
        return {
            "apikey": api_key,
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

    async def fetch_rows(
        self,
        *,
        table: str,
        select: str = "*",
        filters: Optional[Mapping[str, str]] = None,
        order: Optional[str] = None,
        limit: Optional[int] = None,
        offset: Optional[int] = None,
        use_service_key: bool = True,
        timeout_seconds: float = 10.0,
    ) -> List[Dict[str, Any]]:
        if not self.enabled:
            raise RuntimeError("Supabase is not configured.")

        params: Dict[str, str] = {"select": select}
        if filters:
            params.update(filters)
        if order:
            params["order"] = order
        if limit is not None:
            params["limit"] = str(limit)
        if offset is not None:
            params["offset"] = str(offset)

        endpoint = f"{self._base_url}/rest/v1/{table}"
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            response = await client.get(
                endpoint,
                headers=self._headers(use_service_key=use_service_key),
                params=params,
            )
            response.raise_for_status()
            payload = response.json()
            if isinstance(payload, list):
                return [
                    row for row in payload if isinstance(row, dict)
                ]
            return []

    async def insert_row(
        self,
        *,
        table: str,
        row: Mapping[str, Any],
        use_service_key: bool = True,
        timeout_seconds: float = 10.0,
    ) -> Dict[str, Any]:
        if not self.enabled:
            raise RuntimeError("Supabase is not configured.")

        endpoint = f"{self._base_url}/rest/v1/{table}"
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            response = await client.post(
                endpoint,
                headers=self._headers(use_service_key=use_service_key),
                params={"select": "*"},
                json=dict(row),
            )
            response.raise_for_status()
            payload = response.json()
            if isinstance(payload, list) and payload:
                first = payload[0]
                if isinstance(first, dict):
                    return first
            if isinstance(payload, dict):
                return payload
            return {}


supabase_client = SupabaseClient()
