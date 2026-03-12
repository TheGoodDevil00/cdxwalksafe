from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import json
import math

from app.services.reporting_service import reporting_service


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DUMMY_DATA_PATH = PROJECT_ROOT / "logic" / "output" / "pune_dummy_safety_data.geojson"


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius_m = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    )
    return earth_radius_m * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def _classify(score: float) -> str:
    if score >= 70.0:
        return "SAFE"
    if score >= 40.0:
        return "CAUTIOUS"
    return "RISKY"


class SafetyZoneService:
    def __init__(self) -> None:
        self._cache_payload: Optional[Dict[str, Any]] = None
        self._cache_generated_at: Optional[datetime] = None
        self._cache_ttl = timedelta(minutes=5)
        self._incident_radius_m = 250.0
        self._incident_penalty_scale = 20.0
        self._max_penalty = 40.0

    async def get_safety_zones(
        self,
        *,
        force_refresh: bool = False,
        bbox: Optional[Tuple[float, float, float, float]] = None,
        lookback_days: int = 30,
    ) -> Dict[str, Any]:
        now = datetime.now(timezone.utc)
        if (
            not force_refresh
            and self._cache_payload is not None
            and self._cache_generated_at is not None
            and now - self._cache_generated_at <= self._cache_ttl
        ):
            return self._filter_by_bbox(self._cache_payload, bbox)

        segments = self._load_segment_midpoints()
        try:
            incidents = await reporting_service.get_recent_incidents(
                lookback_days=max(1, lookback_days)
            )
        except Exception:
            incidents = []
        zones = self._build_zone_grid(segments, incidents, now=now)

        dataset_version = now.replace(microsecond=0).isoformat().replace("+00:00", "Z")
        geojson = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "Point",
                        "coordinates": [zone["lon"], zone["lat"]],
                    },
                    "properties": {
                        "id": zone["id"],
                        "classification": zone["classification"],
                        "score": zone["score"],
                        "radius_meters": zone["radius_meters"],
                    },
                }
                for zone in zones
            ],
        }

        payload: Dict[str, Any] = {
            "dataset_version": dataset_version,
            "generated_at": dataset_version,
            "valid_until": (
                now + timedelta(minutes=15)
            ).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "incident_count": len(incidents),
            "zones": zones,
            "geojson": geojson,
        }
        self._cache_payload = payload
        self._cache_generated_at = now
        return self._filter_by_bbox(payload, bbox)

    def _load_segment_midpoints(self) -> List[Dict[str, float]]:
        if not DUMMY_DATA_PATH.exists():
            raise RuntimeError(
                f"Safety dataset not found at {DUMMY_DATA_PATH}. "
                "Run logic/datagen.py to generate it."
            )

        with DUMMY_DATA_PATH.open("r", encoding="utf-8") as fp:
            data = json.load(fp)

        features = data.get("features", [])
        segment_points: List[Dict[str, float]] = []
        for feature in features:
            if not isinstance(feature, dict):
                continue
            geometry = feature.get("geometry", {})
            properties = feature.get("properties", {})
            if not isinstance(geometry, dict) or not isinstance(properties, dict):
                continue
            coordinates = geometry.get("coordinates", [])
            if not isinstance(coordinates, list) or len(coordinates) < 2:
                continue

            start = coordinates[0]
            end = coordinates[-1]
            if not isinstance(start, list) or not isinstance(end, list):
                continue
            if len(start) < 2 or len(end) < 2:
                continue

            lon = (_to_float(start[0]) + _to_float(end[0])) / 2.0
            lat = (_to_float(start[1]) + _to_float(end[1])) / 2.0
            base_score = _to_float(properties.get("base_safety_score"), 50.0)

            segment_points.append({"lat": lat, "lon": lon, "base_score": base_score})

        return segment_points

    def _build_zone_grid(
        self,
        segments: List[Dict[str, float]],
        incidents: List[Dict[str, Any]],
        *,
        now: datetime,
    ) -> List[Dict[str, Any]]:
        buckets: Dict[Tuple[int, int], Dict[str, Any]] = {}
        for segment in segments:
            lat = segment["lat"]
            lon = segment["lon"]
            penalty = self._incident_penalty(lat=lat, lon=lon, incidents=incidents, now=now)
            score = max(0.0, min(100.0, segment["base_score"] - penalty))

            key = (int(round(lat * 1000)), int(round(lon * 1000)))
            bucket = buckets.setdefault(
                key,
                {
                    "sum_score": 0.0,
                    "sum_lat": 0.0,
                    "sum_lon": 0.0,
                    "count": 0,
                },
            )
            bucket["sum_score"] += score
            bucket["sum_lat"] += lat
            bucket["sum_lon"] += lon
            bucket["count"] += 1

        zones: List[Dict[str, Any]] = []
        for idx, bucket in enumerate(buckets.values(), start=1):
            if bucket["count"] <= 0:
                continue
            avg_score = bucket["sum_score"] / bucket["count"]
            zone_lat = bucket["sum_lat"] / bucket["count"]
            zone_lon = bucket["sum_lon"] / bucket["count"]
            zones.append(
                {
                    "id": f"zone_{idx}",
                    "lat": round(zone_lat, 6),
                    "lon": round(zone_lon, 6),
                    "radius_meters": 140,
                    "classification": _classify(avg_score),
                    "score": round(avg_score, 2),
                }
            )

        return zones

    def _incident_penalty(
        self,
        *,
        lat: float,
        lon: float,
        incidents: List[Dict[str, Any]],
        now: datetime,
    ) -> float:
        if not incidents:
            return 0.0

        impact = 0.0
        for incident in incidents:
            inc_lat = _to_float(incident.get("lat"), default=9999.0)
            inc_lon = _to_float(incident.get("lon"), default=9999.0)
            distance = _haversine_meters(lat, lon, inc_lat, inc_lon)
            if distance > self._incident_radius_m:
                continue

            status = str(incident.get("status", "pending")).lower()
            if status in {"rejected", "dismissed", "spam"}:
                continue

            severity = min(5.0, max(1.0, _to_float(incident.get("severity"), 3.0)))
            confidence = _to_float(incident.get("confidence_score"), 0.5)
            if confidence > 1.0:
                confidence = min(1.0, confidence / 100.0)
            confidence = max(0.1, min(1.0, confidence))

            created_at = incident.get("created_at")
            recency = self._recency_factor(created_at, now=now)
            distance_factor = max(0.0, 1.0 - (distance / self._incident_radius_m))
            impact += distance_factor * (severity / 5.0) * confidence * recency

        return min(self._max_penalty, impact * self._incident_penalty_scale)

    def _recency_factor(self, created_at: Any, *, now: datetime) -> float:
        if isinstance(created_at, datetime):
            incident_time = created_at
        elif isinstance(created_at, str):
            try:
                incident_time = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
            except ValueError:
                incident_time = now
        else:
            incident_time = now

        if incident_time.tzinfo is None:
            incident_time = incident_time.replace(tzinfo=timezone.utc)
        elapsed_hours = max(0.0, (now - incident_time).total_seconds() / 3600.0)
        return 0.5 ** (elapsed_hours / 72.0)

    def _filter_by_bbox(
        self,
        payload: Dict[str, Any],
        bbox: Optional[Tuple[float, float, float, float]],
    ) -> Dict[str, Any]:
        if bbox is None:
            return payload

        min_lon, min_lat, max_lon, max_lat = bbox
        zones = payload.get("zones", [])
        if not isinstance(zones, list):
            return payload

        filtered_zones = [
            zone
            for zone in zones
            if isinstance(zone, dict)
            and min_lon <= _to_float(zone.get("lon")) <= max_lon
            and min_lat <= _to_float(zone.get("lat")) <= max_lat
        ]

        geojson = payload.get("geojson", {})
        features = geojson.get("features", []) if isinstance(geojson, dict) else []
        filtered_ids = {zone["id"] for zone in filtered_zones if "id" in zone}
        filtered_features = [
            feature
            for feature in features
            if isinstance(feature, dict)
            and isinstance(feature.get("properties"), dict)
            and feature["properties"].get("id") in filtered_ids
        ]

        updated = dict(payload)
        updated["zones"] = filtered_zones
        updated["geojson"] = {
            "type": "FeatureCollection",
            "features": filtered_features,
        }
        return updated


safety_zone_service = SafetyZoneService()
