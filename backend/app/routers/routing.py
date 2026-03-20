from typing import Dict, List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.risk_engine import score_route
from app.services.routing_service import get_safe_route
from app.services.safety_zone_service import get_safety_zones as load_safety_zones

router = APIRouter()


class Coordinate(BaseModel):
    lat: float
    lon: float


class RouteCoordinates(BaseModel):
    coordinates: List[Coordinate]


@router.get("/route", response_model=Dict[str, List[Dict[str, float]]])
async def get_route(
    start_lat: float,
    start_lon: float,
    end_lat: float,
    end_lon: float,
):
    try:
        route = await get_safe_route(start_lat, start_lon, end_lat, end_lon)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return {
        "safest": [
            {"lat": float(lat), "lon": float(lon)}
            for lat, lon in route["coordinates"]
        ]
    }


@router.post("/route/risk")
async def route_risk(
    body: RouteCoordinates,
    db: AsyncSession = Depends(get_db),
):
    coordinates = [(c.lat, c.lon) for c in body.coordinates]
    return await score_route(coordinates, db)


@router.get("/route-safe")
async def route_safe(
    start_lat: float,
    start_lon: float,
    end_lat: float,
    end_lon: float,
    db: AsyncSession = Depends(get_db),
):
    try:
        route = await get_safe_route(start_lat, start_lon, end_lat, end_lon)
    except RuntimeError as exc:
        message = str(exc)
        if "Cannot connect to Valhalla routing engine" in message:
            raise HTTPException(status_code=503, detail=message) from exc
        return {
            "safety_score": None,
            "warning": "No route or safety data found for this route area.",
        }

    score = await score_route(route["coordinates"], db)
    score["coordinates"] = route["coordinates"]
    score["distance_km"] = route["distance_km"]
    score["duration_minutes"] = route["duration_minutes"]
    return score


@router.get("/safety-zones")
async def safety_zones(
    min_lat: float | None = None,
    max_lat: float | None = None,
    min_lon: float | None = None,
    max_lon: float | None = None,
    db: AsyncSession = Depends(get_db),
):
    return await load_safety_zones(
        db,
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
    )
