# WalkSafe Roadmap and Current State

## 1. Project Overview
WalkSafe is a safety-first pedestrian navigation system for Pune, India.  
Instead of optimizing only for shortest distance or fastest ETA, the system scores route segments by safety and recommends lower-risk paths.

Core problem being solved:
- Traditional navigation apps optimize for speed, not personal safety.
- Users need route recommendations informed by incident patterns, street context, and time-of-day risk.
- The app must remain useful even when some services are unavailable (offline overlays and local fallback scoring).

## 2. Current System Architecture
### Mobile layer
- Flutter app renders map, route polyline, safety overlays, and incident reporting UI.
- Primary route fetch path:
1. Request alternative walking routes from OSRM.
2. Decode polylines to latitude/longitude points.
3. Send each candidate route to backend risk endpoint.
4. Select route with lowest `summary.total_risk`.
- If backend risk endpoint is unavailable, mobile falls back to local heuristic scoring using locally stored incident reports.

### Backend layer
- FastAPI app at `/api/v1`.
- `POST /api/v1/route/risk` scores decoded route coordinates using `RiskEngine`.
- RiskEngine loads `logic/output/pune_dummy_safety_data.geojson`, builds spatial index (R-tree or STRtree), maps route points to nearest segments, applies time penalty, and computes segment and route risk.
- Reporting endpoints exist (`/api/v1/reports`, `/api/v1/reports/recent`) but are partially wired and not yet integrated into route scoring.

### Data pipeline layer
- Python scripts in `logic/` build and export safety data.
- `generate_street_graph.py` fetches OSM walk graph for Pune.
- `generate_safety_map.py` computes feature-engineered safety segments and exports `pune_safety_segments.geojson`.
- `datagen.py` overlays pseudorandom zonal risk data, safety levels, and time penalties into `pune_dummy_safety_data.geojson`.

### External services
- OSRM public API for candidate walking routes.
- OpenStreetMap and OSMnx for road graph extraction.
- Supabase used in two places:
1. Flutter SDK initialized in app startup.
2. Logic pipeline has Supabase REST fetch path for incident points.

### Architecture diagram (text)
```text
User tap in Flutter app
  -> Mobile RoutingService
     -> OSRM /route (alternatives=true, polyline)
        -> decode candidate polylines
           -> FastAPI POST /api/v1/route/risk (one call per candidate)
              -> RiskEngine
                 -> load logic/output/pune_dummy_safety_data.geojson
                 -> nearest-segment spatial lookup
                 -> risk = distance_weight + (100 - safety_score)
           -> mobile sorts candidates by total_risk
              -> render safest polyline + summary

Parallel safety lookups:
  Mobile LogicSafetyApiService -> logic/api.py (/safety-score, /safety-map)

Incident reporting today:
  ReportIncidentScreen -> SharedPreferences (local only)
  (backend reports endpoint exists but not used by mobile flow yet)
```

## 3. Technology Stack
- Flutter (Dart): Mobile UI, map interaction, local persistence, and service orchestration.
- flutter_map + OpenStreetMap tiles: Map display and overlays.
- FastAPI (Python): Backend APIs for routing/risk/reporting.
- Python geospatial stack: `shapely`, `geopandas`, `pyproj`, `osmnx` for spatial processing.
- OSRM: External routing engine for route alternatives.
- Supabase:
1. Client SDK initialized in Flutter.
2. REST pull path in logic feature-engineering.
- Postgres/PostGIS (docker-compose): Planned/partial persistence layer for backend.
- SharedPreferences (Flutter): Local incident report cache.

## 4. Repository Structure
### `backend/`
- Purpose: FastAPI APIs, risk engine, reporting services, DB schema.
- Key files:
1. `app/main.py`: app bootstrap and router registration (`/api/v1` prefix).
2. `app/routers/routing.py`: `/route`, `/route/safety`, `/route/risk`.
3. `app/services/risk_engine.py`: current core route risk scoring implementation.
4. `app/routers/reports.py` and `app/services/reporting_service.py`: report submission/retrieval (partial integration).
5. `app/schema.sql`: PostGIS schema draft.

### `logic/`
- Purpose: Spatial data generation and lightweight safety map API.
- Key files:
1. `generate_street_graph.py`: OSMnx graph extraction.
2. `safety_feature_engine.py`: feature scoring and Supabase incident ingestion helpers.
3. `generate_safety_map.py`: produces base segment-level safety GeoJSON.
4. `datagen.py`: pseudorandom zonal safety augmentation and time penalties.
5. `api.py`: serves `/safety-map` and `/safety-score` from generated dataset.
6. `output/pune_safety_segments.geojson`: base engineered dataset.
7. `output/pune_dummy_safety_data.geojson`: active pseudorandom risk dataset used by backend risk engine.

### `mobile/`
- Purpose: Flutter app and map/routing/reporting UX.
- Key files:
1. `lib/services/routing_service.dart`: OSRM fetch + backend `/route/risk` integration + fallback local scoring.
2. `lib/services/safety_score_service.dart`: local heuristic segment scoring.
3. `lib/services/safety_heatmap_service.dart`: static circular safety zones.
4. `lib/services/incident_storage_service.dart`: local incident persistence.
5. `lib/screens/home_screen.dart`: main map workflow and route rendering.
6. `lib/screens/report_incident_screen.dart`: incident report capture.
7. `lib/services/logic_safety_api_service.dart`: calls `logic/api.py` service.

## 5. Current Features Implemented
- Map rendering with OSM tiles and interactive tap-to-route.
- OSRM route alternative fetch and polyline decode in mobile.
- Backend risk scoring endpoint (`POST /api/v1/route/risk`) integrated into mobile route selection.
- Segment-level safety metadata available in route objects (`safety_level`, `safety_score`, etc.).
- Local fallback scoring when backend route-risk API is unavailable.
- Local incident reporting and persistence using SharedPreferences.
- Static safety-zone overlay rendering in mobile.
- Logic API service for nearest-segment score lookups (`/safety-score`).
- Dataset pipeline producing GeoJSON safety segments for Pune.

System interaction summary:
- Routing uses OSRM for geometry and backend RiskEngine for scoring.
- UI overlays combine static local zones and dynamic route safety output.
- Incident reports influence fallback mobile scoring immediately (local only), but not yet full backend live risk updates.

## 6. Safety Zone System
Current implementation uses circular overlays (`SafetyZone`) with score thresholds:
- SAFE: score >= 70
- CAUTIOUS: score 40-69
- RISKY: score < 40

Naming note:
- Mobile enum currently uses `safe`, `moderate`, `unsafe`.
- Backend dummy dataset currently uses `Safe`, `Moderate`, `High Risk`.
- For product docs and future APIs, normalize to SAFE / CAUTIOUS / RISKY.

How it works today:
- Zones are static, hardcoded mock points in `SafetyHeatmapService`.
- Circles are rendered client-side with radius in meters.

Offline capability:
- Because zone data is local, safety overlays render without network.
- This provides degraded-but-usable guidance during API outages or poor connectivity.

## 7. Current Limitations
- Dynamic risk updates are not yet wired end-to-end from live incident ingestion to route scoring.
- Backend report table usage is inconsistent:
1. `reporting_service.py` inserts into `user_reports`.
2. `schema.sql` defines `incidents` but not `user_reports`.
- Mobile report submission is local-only (SharedPreferences), not sent to backend by default.
- Supabase integration exists but is partial and includes hardcoded credentials in code.
- Route-safe endpoint contract is not finalized (`/route/risk` exists; `/route-safe` is not implemented yet).
- Hot-zone propagation to nearby streets is not implemented.
- Legacy/unused mobile structure (`presentation/`, old `ApiClient`) can confuse new contributors.
- No robust caching/versioning strategy yet for safety datasets and map tiles.

## 8. Future Development Roadmap
### Milestone 1: Backend routing engine hardening
1. Replace mock `/route` behavior with real graph-based routing (pgRouting or service-side graph).
2. Keep `/route/risk` for scoring decoded candidates or evolve to consolidated `/route-safe`.
3. Add structured error contracts and telemetry.

### Milestone 2: Supabase-first incident pipeline
1. Normalize schema (`incident_reports`, `emergency_alerts`, and supporting indices).
2. Send mobile reports to backend and persist in Supabase/Postgres.
3. Backfill migration scripts and environment-based secret handling.

### Milestone 3: Real-time risk scoring updates
1. Inject recent incidents into RiskEngine scoring path.
2. Implement spatial propagation decay around incident points.
3. Add time-window weighting and confidence scoring.

### Milestone 4: Offline zone optimization
1. Generate compact tile or clustered zone artifacts for mobile caching.
2. Version datasets and support incremental updates.
3. Add fallback strategy for stale data age and network outages.

### Milestone 5: UX and reliability
1. Expose route safety explanation (why a route is safer).
2. Add integration tests across OSRM -> backend -> mobile.
3. Add CI checks for schema consistency and endpoint contracts.
