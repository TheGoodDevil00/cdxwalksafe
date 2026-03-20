"""
Safety Zone Service - serves polygon zones from the database.
Never returns hardcoded, random, or point-based zones.
"""

import json

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def get_safety_zones(
    db: AsyncSession,
    min_lat: float | None = None,
    max_lat: float | None = None,
    min_lon: float | None = None,
    max_lon: float | None = None,
) -> dict:
    """
    Return GeoJSON FeatureCollection of safety zone polygons within the bounding box.
    """
    query = """
        SELECT
            zone_id,
            ST_AsGeoJSON(geometry)::text AS geojson,
            risk_level,
            risk_score,
            dataset_version
        FROM safety_zones
        WHERE dataset_version = (
            SELECT dataset_version FROM safety_zones
            ORDER BY created_at DESC LIMIT 1
        )
    """

    params = {}
    if None not in (min_lat, max_lat, min_lon, max_lon):
        query += """
            AND geometry && ST_MakeEnvelope(
                :min_lon, :min_lat, :max_lon, :max_lat, 4326
            )
        """
        params = {
            "min_lat": min_lat,
            "max_lat": max_lat,
            "min_lon": min_lon,
            "max_lon": max_lon,
        }

    result = await db.execute(text(query), params)
    rows = result.fetchall()

    if not rows:
        return {
            "type": "FeatureCollection",
            "features": [],
            "data_warning": "No zone data loaded. Run logic/generate_safety_map.py first.",
        }

    features = []
    for row in rows:
        features.append(
            {
                "type": "Feature",
                "geometry": json.loads(row[1]),
                "properties": {
                    "zone_id": row[0],
                    "risk_level": row[2],
                    "risk_score": row[3],
                    "dataset_version": row[4],
                },
            }
        )

    return {"type": "FeatureCollection", "features": features}
