from __future__ import annotations

from typing import Any, Dict, List

import httpx


class OsrmService:
    def __init__(
        self,
        *,
        base_url: str = "https://router.project-osrm.org",
        timeout_seconds: float = 12.0,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout_seconds = timeout_seconds

    async def fetch_walking_routes(
        self,
        *,
        start_lat: float,
        start_lon: float,
        end_lat: float,
        end_lon: float,
        alternatives: int = 3,
    ) -> List[Dict[str, Any]]:
        request_url = (
            f"{self._base_url}/route/v1/foot/"
            f"{start_lon},{start_lat};{end_lon},{end_lat}"
        )
        params = {
            "overview": "full",
            "geometries": "geojson",
            "alternatives": "true",
            "steps": "false",
        }

        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
            response = await client.get(request_url, params=params)
            response.raise_for_status()
            payload = response.json()

        if payload.get("code") != "Ok":
            raise RuntimeError(f"OSRM response was not OK: {payload.get('code')}")

        route_objects = payload.get("routes", [])
        if not isinstance(route_objects, list):
            return []

        normalized_routes: List[Dict[str, Any]] = []
        max_routes = max(1, int(alternatives))
        for route in route_objects[:max_routes]:
            if not isinstance(route, dict):
                continue
            geometry = route.get("geometry", {})
            if not isinstance(geometry, dict):
                continue
            coordinates = geometry.get("coordinates", [])
            if not isinstance(coordinates, list) or len(coordinates) < 2:
                continue

            normalized_routes.append(
                {
                    "distance": float(route.get("distance", 0.0) or 0.0),
                    "duration": float(route.get("duration", 0.0) or 0.0),
                    "coordinates": coordinates,
                }
            )

        return normalized_routes


osrm_service = OsrmService()
