"""
Risk Engine - reads from road_segments table only.
Never generates, randomises, or invents safety scores.
"""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def score_route(
    coordinates: list[tuple[float, float]],
    db: AsyncSession,
) -> dict:
    """
    Given a list of (lat, lon) waypoints, return the route's safety score.
    Score is derived entirely from road_segments in the database.
    Returns None score (not zero) if no data exists for this area.
    """
    if not coordinates or len(coordinates) < 2:
        return {"safety_score": None, "warning": "Route has no coordinates"}

    lats = [c[0] for c in coordinates]
    lons = [c[1] for c in coordinates]
    bbox = {
        "min_lat": min(lats) - 0.001,
        "max_lat": max(lats) + 0.001,
        "min_lon": min(lons) - 0.001,
        "max_lon": max(lons) + 0.001,
    }

    result = await db.execute(
        text(
            """
            SELECT safety_score, ST_Length(geometry::geography) AS length_m
            FROM road_segments
            WHERE geometry && ST_MakeEnvelope(
                :min_lon, :min_lat, :max_lon, :max_lat, 4326
            )
            AND dataset_version = (
                SELECT dataset_version FROM road_segments
                ORDER BY updated_at DESC LIMIT 1
            )
            """
        ),
        bbox,
    )

    rows = result.fetchall()

    if not rows:
        return {
            "safety_score": None,
            "warning": (
                "No safety data found for this route area. "
                "The ingest job may not have been run yet."
            ),
        }

    total_length = sum(r[1] for r in rows)
    if total_length == 0:
        return {"safety_score": None, "warning": "Route segments have zero length"}

    weighted_score = sum(r[0] * r[1] for r in rows) / total_length

    return {
        "safety_score": round(weighted_score, 1),
        "segment_count": len(rows),
        "warning": None,
    }
