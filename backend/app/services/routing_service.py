import os

import httpx
import polyline
from dotenv import load_dotenv

load_dotenv()

VALHALLA_BASE_URL = os.environ.get("VALHALLA_BASE_URL", "http://localhost:8002")


async def get_safe_route(
    start_lat: float,
    start_lon: float,
    end_lat: float,
    end_lon: float,
) -> dict:
    """
    Fetch a pedestrian route from Valhalla.
    Returns decoded polyline coordinates and route metadata.
    """
    payload = {
        "locations": [
            {"lat": start_lat, "lon": start_lon},
            {"lat": end_lat, "lon": end_lon},
        ],
        "costing": "pedestrian",
        "costing_options": {
            "pedestrian": {
                "use_lit": 1.0,
                "use_roads": 0.2,
                "walkway_factor": 0.8,
                "sidewalk_factor": 0.9,
            }
        },
        "directions_options": {"units": "kilometers"},
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.post(
                f"{VALHALLA_BASE_URL}/route",
                json=payload,
            )
            response.raise_for_status()
        except httpx.ConnectError as exc:
            raise RuntimeError(
                "Cannot connect to Valhalla routing engine. "
                "Make sure Docker is running and Valhalla started with: "
                "docker compose -f backend/docker-compose.yml up valhalla"
            ) from exc
        except httpx.HTTPStatusError as exc:
            raise RuntimeError(
                f"Valhalla returned an error: {exc.response.text}"
            ) from exc

    data = response.json()
    encoded = data["trip"]["legs"][0]["shape"]
    coordinates = polyline.decode(encoded, precision=6)
    summary = data["trip"]["summary"]

    return {
        "coordinates": coordinates,
        "distance_km": summary["length"],
        "duration_minutes": summary["time"] / 60,
        "safety_score": None,
    }


class RoutingService:
    async def get_safe_route(
        self,
        start_lat: float,
        start_lon: float,
        end_lat: float,
        end_lon: float,
    ) -> dict:
        return await get_safe_route(start_lat, start_lon, end_lat, end_lon)


routing_service = RoutingService()
