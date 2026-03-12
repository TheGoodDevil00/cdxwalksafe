from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import geopandas as gpd
from pyproj import Transformer
from shapely.geometry import LineString, MultiLineString, Point
from shapely.ops import linemerge, transform

try:
    from logic.generate_street_graph import (
        PUNE_CENTER_LAT,
        PUNE_CENTER_LON,
        PUNE_RADIUS_METERS,
        generate_street_graph,
    )
    from logic.safety_feature_engine import (
        SafetyFeatureEngine,
        load_incidents_from_supabase,
    )
except ImportError:  # pragma: no cover
    # Allows running this module directly from the logic directory.
    from generate_street_graph import (
        PUNE_CENTER_LAT,
        PUNE_CENTER_LON,
        PUNE_RADIUS_METERS,
        generate_street_graph,
    )
    from safety_feature_engine import (
        SafetyFeatureEngine,
        load_incidents_from_supabase,
    )

OUTPUT_PATH = Path(__file__).resolve().parent / "output" / "pune_safety_segments.geojson"
WGS84_CRS = "EPSG:4326"
METRIC_CRS = "EPSG:32643"  # UTM zone covering Pune.


def generate_safety_map(
    *,
    lat: float = PUNE_CENTER_LAT,
    lon: float = PUNE_CENTER_LON,
    radius_meters: int = PUNE_RADIUS_METERS,
    output_path: Path | str = OUTPUT_PATH,
) -> gpd.GeoDataFrame:
    """Generates per-segment safety scores and writes a GeoJSON dataset."""
    # Step 1: Fetch walkable street graph and edge geometries for the region.
    graph, nodes_gdf, edges_gdf = generate_street_graph(
        lat=lat,
        lon=lon,
        radius_meters=radius_meters,
        network_type="walk",
    )

    edges_wgs84 = edges_gdf.copy()
    if edges_wgs84.crs is None:
        edges_wgs84 = edges_wgs84.set_crs(WGS84_CRS, allow_override=True)
    else:
        edges_wgs84 = edges_wgs84.to_crs(WGS84_CRS)

    edges_metric = edges_wgs84.to_crs(METRIC_CRS)
    metric_geometry_by_index = {
        idx: _normalize_linestring(geom) for idx, geom in edges_metric.geometry.items()
    }

    # Step 2: Build intersection points (for crowd density heuristic).
    intersection_points_wgs84 = _extract_intersection_points(graph)
    intersection_points_metric = _project_points(intersection_points_wgs84)

    # Step 3: Load incident reports from Supabase and project to metric CRS.
    incidents = load_incidents_from_supabase()
    incident_points_wgs84 = [
        Point(float(item["lon"]), float(item["lat"]))
        for item in incidents
        if "lat" in item and "lon" in item
    ]
    incident_points_metric = _project_points(incident_points_wgs84)

    feature_engine = SafetyFeatureEngine(
        incident_points_metric=incident_points_metric,
        intersection_points_metric=intersection_points_metric,
    )

    # Step 4: Score each street segment and build output records.
    to_metric = Transformer.from_crs(WGS84_CRS, METRIC_CRS, always_xy=True)
    records: List[Dict[str, Any]] = []

    for edge_idx, edge_row in edges_wgs84.iterrows():
        segment_geom_wgs84 = _normalize_linestring(edge_row.geometry)
        if segment_geom_wgs84 is None:
            segment_geom_wgs84 = _build_geometry_from_nodes(edge_idx, nodes_gdf)
        if segment_geom_wgs84 is None:
            continue

        segment_geom_metric = metric_geometry_by_index.get(edge_idx)
        if segment_geom_metric is None:
            segment_geom_metric = transform(to_metric.transform, segment_geom_wgs84)

        features = feature_engine.score_segment(
            segment_geometry_metric=segment_geom_metric,
            road_type=edge_row.get("highway"),
        )

        (start_lon, start_lat), (end_lon, end_lat) = _line_endpoints(segment_geom_wgs84)
        edge_length = edge_row.get("length")
        distance_meters = (
            float(edge_length)
            if isinstance(edge_length, (int, float)) and edge_length > 0
            else float(segment_geom_metric.length)
        )

        records.append(
            {
                "segment_id": _segment_id(edge_idx),
                "start_lat": float(start_lat),
                "start_lon": float(start_lon),
                "end_lat": float(end_lat),
                "end_lon": float(end_lon),
                "distance": round(distance_meters, 2),
                "incident_count": features.incident_count,
                "lighting_score": round(features.lighting_score, 2),
                "crowd_density": round(features.crowd_density, 2),
                "time_of_day_factor": round(features.time_of_day_factor, 3),
                "safety_score": round(features.safety_score, 2),
                "geometry": segment_geom_wgs84,
            }
        )

    output_gdf = gpd.GeoDataFrame(records, geometry="geometry", crs=WGS84_CRS)

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_gdf.to_file(output_path, driver="GeoJSON")
    return output_gdf


def generate_safety_dataset(**kwargs: Any) -> gpd.GeoDataFrame:
    """Alias used by API startup."""
    return generate_safety_map(**kwargs)


def _extract_intersection_points(graph: Any) -> List[Point]:
    intersection_points: List[Point] = []
    for node_id, degree in graph.degree():
        if degree < 3:
            continue
        node_data = graph.nodes[node_id]
        x = node_data.get("x")
        y = node_data.get("y")
        if x is None or y is None:
            continue
        intersection_points.append(Point(float(x), float(y)))
    return intersection_points


def _project_points(points: List[Point]) -> List[Point]:
    if not points:
        return []
    projected = gpd.GeoSeries(points, crs=WGS84_CRS).to_crs(METRIC_CRS)
    return list(projected)


def _normalize_linestring(geometry: Any) -> Optional[LineString]:
    if geometry is None or getattr(geometry, "is_empty", True):
        return None
    if isinstance(geometry, LineString):
        return geometry
    if isinstance(geometry, MultiLineString):
        merged = linemerge(geometry)
        if isinstance(merged, LineString):
            return merged
        if isinstance(merged, MultiLineString):
            return max(merged.geoms, key=lambda geom: geom.length, default=None)
    return None


def _build_geometry_from_nodes(
    edge_idx: Any,
    nodes_gdf: gpd.GeoDataFrame,
) -> Optional[LineString]:
    if not isinstance(edge_idx, tuple) or len(edge_idx) < 2:
        return None

    u, v = edge_idx[0], edge_idx[1]
    if u not in nodes_gdf.index or v not in nodes_gdf.index:
        return None

    start_node = nodes_gdf.loc[u]
    end_node = nodes_gdf.loc[v]
    return LineString([(start_node["x"], start_node["y"]), (end_node["x"], end_node["y"])])


def _line_endpoints(line: LineString) -> Tuple[Tuple[float, float], Tuple[float, float]]:
    coords = list(line.coords)
    start_lon, start_lat = coords[0]
    end_lon, end_lat = coords[-1]
    return (start_lon, start_lat), (end_lon, end_lat)


def _segment_id(edge_idx: Any) -> str:
    if isinstance(edge_idx, tuple):
        return "_".join(str(item) for item in edge_idx)
    return str(edge_idx)


if __name__ == "__main__":
    gdf = generate_safety_map()
    print(
        f"Generated {len(gdf)} segments and saved to {OUTPUT_PATH.as_posix()}",
    )
