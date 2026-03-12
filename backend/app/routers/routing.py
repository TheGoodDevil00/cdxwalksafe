from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services.osrm_service import osrm_service
from app.services.risk_engine import RiskEngine
from app.services.safety_zone_service import safety_zone_service


router = APIRouter()
risk_engine = RiskEngine()


class Coordinate(BaseModel):
    lat: float
    lon: float


class RouteCoordinates(BaseModel):
    coordinates: List[Coordinate]


@router.get("/route", response_model=Dict[str, List[Dict]])
async def get_routes(start_lat: float, start_lon: float, end_lat: float, end_lon: float):
    """
    Returns multiple routes: Safest, Fast, Balanced.
    Currently returns mock data until A* is implemented.
    """
    # TODO: Implement actual A* or Dijkstra on PostGIS pgRouting
    return {
        "safest": [
            {"lat": start_lat, "lon": start_lon},
            {"lat": (start_lat + end_lat)/2, "lon": (start_lon + end_lon)/2}, 
            {"lat": end_lat, "lon": end_lon}
        ],
        "fastest": [
            {"lat": start_lat, "lon": start_lon},
            {"lat": end_lat, "lon": end_lon}
        ]
    }


@router.get("/route/safety")
async def get_route_safety(start_lat: float, start_lon: float, end_lat: float, end_lon: float):
    """
    Returns a simple mock route annotated with safety scores and risk per segment,
    using the dummy safety dataset and the global risk formula:

        risk = distance_weight + (100 - safety_score)
    """
    # For now we mirror the mock "safest" route shape from /route.
    path = [
        {"lat": start_lat, "lon": start_lon},
        {"lat": (start_lat + end_lat) / 2.0, "lon": (start_lon + end_lon) / 2.0},
        {"lat": end_lat, "lon": end_lon},
    ]

    return await risk_engine.score_route(path)


@router.post("/route/risk")
async def score_osrm_route(body: RouteCoordinates):
    """
    Accepts a decoded OSRM route polyline (list of coordinates) and returns
    per-segment safety metrics + aggregate risk using the dummy safety dataset.
    """
    coordinates = [{"lat": c.lat, "lon": c.lon} for c in body.coordinates]
    return await risk_engine.score_route(coordinates)


@router.get("/route-safe")
async def get_route_safe(
    start_lat: float,
    start_lon: float,
    end_lat: float,
    end_lon: float,
    alternatives: int = 3,
):
    """
    Returns the safest route by fetching OSRM alternatives and applying
    dynamic risk scoring to each candidate.
    """
    max_alternatives = max(1, min(alternatives, 5))

    try:
        candidate_routes = await osrm_service.fetch_walking_routes(
            start_lat=start_lat,
            start_lon=start_lon,
            end_lat=end_lat,
            end_lon=end_lon,
            alternatives=max_alternatives,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to fetch baseline routes from OSRM: {exc}",
        )

    if not candidate_routes:
        raise HTTPException(status_code=404, detail="No candidate routes found.")

    ranked_routes: List[Dict[str, Any]] = []
    for candidate in candidate_routes:
        coordinates = _to_route_coordinates(candidate.get("coordinates", []))
        if len(coordinates) < 2:
            continue

        scored = await risk_engine.score_route(coordinates)
        summary = dict(scored.get("summary", {}))
        summary["osrm_distance"] = float(candidate.get("distance", 0.0) or 0.0)
        summary["osrm_duration"] = float(candidate.get("duration", 0.0) or 0.0)

        ranked_routes.append(
            {
                "coordinates": coordinates,
                "segments": scored.get("segments", []),
                "summary": summary,
            }
        )

    if not ranked_routes:
        raise HTTPException(status_code=404, detail="No scoreable routes found.")

    ranked_routes.sort(
        key=lambda route: (
            float(route.get("summary", {}).get("total_risk", float("inf"))),
            float(route.get("summary", {}).get("total_distance", float("inf"))),
        )
    )

    selected_route = ranked_routes[0]
    alternatives_payload = ranked_routes[1:]
    evaluated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    return {
        "selected_route": selected_route,
        "alternatives": alternatives_payload,
        "meta": {
            "evaluated_at": evaluated_at,
            "source": "osrm+risk_engine",
            "formula": "risk = distance_weight + (100 - safety_score)",
        },
    }


@router.get("/safety-zones")
async def get_safety_zones(
    bbox: Optional[str] = None,
    version: Optional[str] = None,
    refresh: bool = False,
):
    """
    Returns safety zones for overlay rendering and offline cache sync.
    """
    parsed_bbox = _parse_bbox(bbox) if bbox else None
    payload = await safety_zone_service.get_safety_zones(
        force_refresh=refresh,
        bbox=parsed_bbox,
    )

    if version and version == payload.get("dataset_version"):
        return {
            "dataset_version": payload.get("dataset_version"),
            "generated_at": payload.get("generated_at"),
            "valid_until": payload.get("valid_until"),
            "zones": [],
            "geojson": {"type": "FeatureCollection", "features": []},
            "not_modified": True,
        }

    return payload


def _to_route_coordinates(coordinates: Any) -> List[Dict[str, float]]:
    if not isinstance(coordinates, list):
        return []
    normalized: List[Dict[str, float]] = []
    for point in coordinates:
        if not isinstance(point, list) or len(point) < 2:
            continue
        lon, lat = point[0], point[1]
        try:
            normalized.append({"lat": float(lat), "lon": float(lon)})
        except (TypeError, ValueError):
            continue
    return normalized


def _parse_bbox(raw_bbox: str) -> Tuple[float, float, float, float]:
    try:
        min_lon_str, min_lat_str, max_lon_str, max_lat_str = raw_bbox.split(",")
        min_lon = float(min_lon_str)
        min_lat = float(min_lat_str)
        max_lon = float(max_lon_str)
        max_lat = float(max_lat_str)
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid bbox format, expected minLon,minLat,maxLon,maxLat: {exc}",
        )

    if min_lon >= max_lon or min_lat >= max_lat:
        raise HTTPException(status_code=422, detail="Invalid bbox bounds.")

    return min_lon, min_lat, max_lon, max_lat
