from __future__ import annotations

import logging
import numbers
import os
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional

import httpx
from shapely.geometry import LineString, Point
from shapely.strtree import STRtree

DEFAULT_SUPABASE_URL = ""
DEFAULT_SUPABASE_ANON_KEY = ""
DEFAULT_INCIDENT_TABLE = "incident_reports"

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class SegmentFeatureResult:
    incident_count: int
    lighting_score: float
    crowd_density: float
    time_of_day_factor: float
    safety_score: float


class SafetyFeatureEngine:
    """Computes segment-level safety features and final 0-100 safety score."""

    def __init__(
        self,
        *,
        incident_points_metric: Optional[List[Point]] = None,
        intersection_points_metric: Optional[List[Point]] = None,
        incident_search_radius_m: float = 75.0,
        intersection_radius_m: float = 120.0,
    ) -> None:
        self._incident_points = incident_points_metric or []
        self._intersection_points = intersection_points_metric or []
        self._incident_search_radius_m = incident_search_radius_m
        self._intersection_radius_m = intersection_radius_m

        self._incident_tree = STRtree(self._incident_points) if self._incident_points else None
        self._intersection_tree = (
            STRtree(self._intersection_points) if self._intersection_points else None
        )

    def score_segment(
        self,
        *,
        segment_geometry_metric: LineString,
        road_type: Any,
        at_time: Optional[datetime] = None,
    ) -> SegmentFeatureResult:
        """Returns all engineered features and the final safety score."""
        # Step 1: Count nearby incidents from the Supabase incident table.
        incident_count = self._count_nearby_points(
            tree=self._incident_tree,
            points=self._incident_points,
            target_geometry=segment_geometry_metric,
            radius_meters=self._incident_search_radius_m,
        )

        # Step 2: Estimate lighting score from road type category.
        lighting_score = self._estimate_lighting_score(road_type)

        # Step 3: Estimate crowd density from road type + nearby intersections.
        intersection_count = self._count_nearby_points(
            tree=self._intersection_tree,
            points=self._intersection_points,
            target_geometry=segment_geometry_metric,
            radius_meters=self._intersection_radius_m,
        )
        crowd_density = self._estimate_crowd_density(road_type, intersection_count)

        # Step 4: Estimate time-of-day safety factor.
        timestamp = at_time or datetime.now()
        time_of_day_factor = self._time_of_day_factor(timestamp.hour)

        # Step 5: Combine factors into a final 0-100 segment safety score.
        safety_score = self._compute_safety_score(
            incident_count=incident_count,
            lighting_score=lighting_score,
            crowd_density=crowd_density,
            time_of_day_factor=time_of_day_factor,
        )

        return SegmentFeatureResult(
            incident_count=incident_count,
            lighting_score=lighting_score,
            crowd_density=crowd_density,
            time_of_day_factor=time_of_day_factor,
            safety_score=safety_score,
        )

    def _count_nearby_points(
        self,
        *,
        tree: Optional[STRtree],
        points: List[Point],
        target_geometry: LineString,
        radius_meters: float,
    ) -> int:
        if tree is None or not points:
            return 0

        search_area = target_geometry.buffer(radius_meters)
        candidates = tree.query(search_area)
        count = 0

        for candidate in candidates:
            candidate_point = self._resolve_candidate_geometry(candidate, points)
            if candidate_point is None:
                continue
            if target_geometry.distance(candidate_point) <= radius_meters:
                count += 1

        return count

    def _resolve_candidate_geometry(
        self,
        candidate: Any,
        points: List[Point],
    ) -> Optional[Point]:
        # Shapely STRtree may return geometry objects or integer indices.
        if isinstance(candidate, numbers.Integral):
            idx = int(candidate)
            if 0 <= idx < len(points):
                return points[idx]
            return None

        if isinstance(candidate, Point):
            return candidate

        return None

    def _estimate_lighting_score(self, road_type: Any) -> float:
        road = _normalize_road_type(road_type)
        score_by_road = {
            "motorway": 90,
            "trunk": 88,
            "primary": 82,
            "secondary": 75,
            "tertiary": 68,
            "residential": 58,
            "living_street": 62,
            "service": 52,
            "pedestrian": 57,
            "footway": 48,
            "path": 42,
            "steps": 35,
            "track": 38,
        }
        return _clamp(score_by_road.get(road, 55), 0, 100)

    def _estimate_crowd_density(self, road_type: Any, intersection_count: int) -> float:
        road = _normalize_road_type(road_type)
        base_by_road = {
            "motorway": 20,
            "trunk": 30,
            "primary": 58,
            "secondary": 64,
            "tertiary": 60,
            "residential": 50,
            "living_street": 56,
            "service": 40,
            "pedestrian": 72,
            "footway": 54,
            "path": 35,
            "steps": 30,
            "track": 25,
        }
        base_density = base_by_road.get(road, 50)
        intersection_boost = min(30, intersection_count * 6)
        return _clamp(base_density + intersection_boost, 0, 100)

    def _time_of_day_factor(self, hour: int) -> float:
        if 7 <= hour <= 18:
            return 1.0
        if 5 <= hour <= 6 or 19 <= hour <= 20:
            return 0.7
        if 21 <= hour <= 22:
            return 0.5
        return 0.3

    def _compute_safety_score(
        self,
        *,
        incident_count: int,
        lighting_score: float,
        crowd_density: float,
        time_of_day_factor: float,
    ) -> float:
        # Weighted risk components (higher = more unsafe).
        incident_risk = min(1.0, incident_count / 5.0)
        lighting_risk = 1.0 - (lighting_score / 100.0)
        crowd_risk = 1.0 - (crowd_density / 100.0)
        time_risk = 1.0 - time_of_day_factor

        total_risk = (
            (0.45 * incident_risk)
            + (0.25 * lighting_risk)
            + (0.20 * crowd_risk)
            + (0.10 * time_risk)
        )
        safety_score = (1.0 - total_risk) * 100.0
        return round(_clamp(safety_score, 0, 100), 2)


def load_incidents_from_supabase(
    *,
    supabase_url: Optional[str] = None,
    supabase_anon_key: Optional[str] = None,
    table_name: str = DEFAULT_INCIDENT_TABLE,
    page_size: int = 1000,
    timeout_seconds: float = 15.0,
) -> List[Dict[str, Any]]:
    """Reads incident rows from Supabase REST API and returns lat/lon records."""
    base_url = (supabase_url or os.getenv("SUPABASE_URL") or DEFAULT_SUPABASE_URL).strip()
    anon_key = (
        supabase_anon_key
        or os.getenv("SUPABASE_ANON_KEY")
        or DEFAULT_SUPABASE_ANON_KEY
    ).strip()

    if not base_url or not anon_key:
        LOGGER.warning("Supabase credentials not configured, using empty incident set.")
        return []

    endpoint = f"{base_url.rstrip('/')}/rest/v1/{table_name}"
    headers = {
        "apikey": anon_key,
        "Authorization": f"Bearer {anon_key}",
    }

    incidents: List[Dict[str, Any]] = []
    offset = 0

    try:
        with httpx.Client(timeout=timeout_seconds) as client:
            while True:
                response = client.get(
                    endpoint,
                    headers=headers,
                    params={"select": "*", "limit": page_size, "offset": offset},
                )
                response.raise_for_status()
                rows = response.json()
                if not isinstance(rows, list):
                    break

                for row in rows:
                    lat, lon = _extract_lat_lon(row)
                    if lat is None or lon is None:
                        continue
                    incidents.append(
                        {
                            "lat": lat,
                            "lon": lon,
                            "created_at": row.get("created_at")
                            or row.get("createdAtIso")
                            or row.get("timestamp"),
                        }
                    )

                if len(rows) < page_size:
                    break
                offset += page_size
    except Exception as exc:  # pragma: no cover - network failures are non-fatal
        LOGGER.warning("Failed to load incidents from Supabase: %s", exc)
        return []

    return incidents


def _extract_lat_lon(row: Dict[str, Any]) -> tuple[Optional[float], Optional[float]]:
    lat_keys = ("latitude", "lat", "start_lat")
    lon_keys = ("longitude", "lon", "lng", "start_lon")

    lat = _first_numeric(row, lat_keys)
    lon = _first_numeric(row, lon_keys)
    return lat, lon


def _first_numeric(row: Dict[str, Any], keys: Iterable[str]) -> Optional[float]:
    for key in keys:
        value = row.get(key)
        if value is None:
            continue
        try:
            return float(value)
        except (TypeError, ValueError):
            continue
    return None


def _normalize_road_type(road_type: Any) -> str:
    if isinstance(road_type, (list, tuple, set)) and road_type:
        return str(next(iter(road_type))).lower()
    if road_type is None:
        return "unknown"
    return str(road_type).lower()


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))
