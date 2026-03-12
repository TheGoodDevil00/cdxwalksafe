# Backend Expansion Guide (Production Path)

## 1. Backend Architecture
Target a modular FastAPI backend with four core domains:

1. Routing service
- Responsibility: candidate path generation and route orchestration.
- Current state: `/api/v1/route` returns mock paths; `app/services/routing_service.py` is prototype-only.
- Production target: compute realistic candidates (pgRouting or precomputed graph), then score and rank.

2. Risk engine
- Responsibility: segment-level and route-level risk scoring.
- Current state: `app/services/risk_engine.py` maps decoded route coordinates to nearest safety segments from `logic/output/pune_dummy_safety_data.geojson`.
- Formula currently used:
`risk = distance_weight + (100 - safety_score)`
- Production target: include live incident density, severity, recency decay, and propagation.

3. Incident reporting service
- Responsibility: ingest, validate, deduplicate, and persist incident reports.
- Current state: `reporting_service.py` writes to `user_reports`, but DB schema currently defines `incidents`; schema alignment is required.

4. Safety zone generator
- Responsibility: produce and serve zone/segment datasets for online and offline clients.
- Current state: `logic/generate_safety_map.py` + `logic/datagen.py` create GeoJSON datasets; `logic/api.py` serves map and nearest-score endpoints.
- Production target: scheduled generation, versioning, cache headers, and compact mobile artifacts.

Recommended runtime split:
- API process: `backend/app/main.py` (routing + reports + risk scoring).
- Data process: `logic` pipeline jobs (periodic dataset generation).
- Optional: separate safety-data microservice if load increases.

## 2. Supabase Database Integration
Use Supabase Postgres as the primary persistence system.

Required tables:

### `incident_reports`
Purpose:
- Store user-reported safety incidents.
- Feed risk scoring and hotspot generation.

Suggested schema:
```sql
create table if not exists incident_reports (
  id uuid primary key default gen_random_uuid(),
  user_hash text not null,
  incident_type text not null,
  description text,
  severity smallint not null default 3,
  status text not null default 'pending',
  confidence_score numeric(5,2) not null default 0.50,
  latitude double precision not null,
  longitude double precision not null,
  location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(longitude, latitude), 4326)
  ) stored,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_incident_reports_location
  on incident_reports using gist (location);
create index if not exists idx_incident_reports_created_at
  on incident_reports (created_at desc);
create index if not exists idx_incident_reports_status
  on incident_reports (status);
```

### `emergency_alerts`
Purpose:
- Persist SOS events and contact-notification attempts.

Suggested schema:
```sql
create table if not exists emergency_alerts (
  id uuid primary key default gen_random_uuid(),
  user_hash text not null,
  latitude double precision not null,
  longitude double precision not null,
  location geography(point, 4326) generated always as (
    st_setsrid(st_makepoint(longitude, latitude), 4326)
  ) stored,
  status text not null default 'triggered',
  message text,
  contacts_notified integer not null default 0,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_emergency_alerts_location
  on emergency_alerts using gist (location);
create index if not exists idx_emergency_alerts_created_at
  on emergency_alerts (created_at desc);
```

Implementation note:
- Align backend code and SQL schema to one canonical table naming strategy.
- Do not keep mixed `incidents` vs `user_reports` vs `incident_reports`.

## 3. Configuring Supabase API Keys
### Required environment variables
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_KEY`

### Where to store keys
- Backend: `backend/.env` (never commit).
- Local shell/CI: secret store or environment-injected runtime vars.
- Mobile: only public anon key in app builds; never embed service key in mobile.

### Backend setup steps
1. Create `backend/.env`:
```env
DATABASE_URL=postgresql://admin:password@localhost:5432/safewalk
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<anon-key>
SUPABASE_SERVICE_KEY=<service-role-key>
```
2. Extend `backend/app/database.py` settings model to include Supabase keys.
3. Add a backend Supabase client wrapper (single module, dependency injected).
4. Use `SUPABASE_SERVICE_KEY` only on trusted backend paths (write/admin operations).
5. Keep mobile and public clients on `SUPABASE_ANON_KEY` only.

Security note:
- Current repository contains hardcoded Supabase credentials in `mobile/lib/main.dart` and `logic/safety_feature_engine.py`. Move these to environment-based config.

## 4. Incident Reports and Risk Scoring
How incident reports should affect safety:
1. Incident density increases risk for nearby segments.
2. Severity changes weight (for example, harassment/stalking > poor lighting).
3. Recency decay reduces old incident impact over time.
4. Verified reports carry higher confidence than unverified reports.
5. Spatial propagation spreads partial risk to neighboring streets.

Suggested scoring flow:
1. Fetch incidents in a bounded time window (for example, last 30 days).
2. Spatial join incidents to segment buffers.
3. Compute `incident_component` by severity * confidence * recency.
4. Blend with static features:
- lighting,
- crowd proxy,
- road type,
- time-of-day factor.
5. Emit final `safety_score` and `risk` per segment.

Current implemented baseline:
- Backend RiskEngine uses dataset-provided pseudorandom fields and global time penalties.
- Mobile fallback safety service uses local SharedPreferences incident reports with heuristic scoring.

## 5. Hot Zone Generation
Classify areas into:
- `safe`
- `cautious`
- `risky`

Proposed zone generation pipeline:
1. Build weighted point field from incident reports.
2. Run clustering or kernel density (grid-based or hex-based) within city extent.
3. Map score thresholds:
- score >= 70 -> safe
- 40-69 -> cautious
- <40 -> risky
4. Convert clusters to display primitives:
- circle zones for lightweight mobile rendering,
- optional polygon contours for dense areas.
5. Cache output with version metadata and generation timestamp.

Cache strategy:
- Persist generated zones in object storage or table (`safety_zone_snapshots`).
- Include `dataset_version`, `generated_at`, `valid_until`.
- Serve latest stable version by default.

## 6. Offline Safety Zones
Current dataset artifacts:
- `logic/output/pune_safety_segments.geojson` (base engineered segment data)
- `logic/output/pune_dummy_safety_data.geojson` (active pseudorandom segment data with `safety_level`, `base_safety_score`, `time_penalties`)

GeoJSON behavior:
- FeatureCollection of line segments (`LineString`) with per-segment properties.
- Properties include segment id, endpoints, distance, and safety-related attributes.

Offline flow recommendation:
1. Backend publishes latest zone/segment dataset with version.
2. Mobile downloads and caches dataset (local file/db).
3. Mobile renders circles/polylines from cache when network is unavailable.
4. On reconnect, mobile checks version endpoint and refreshes only if newer.

Current mobile status:
- Offline safety overlays are currently static mock circles (`SafetyHeatmapService`), not yet synced from backend-generated GeoJSON.

## 7. Backend API Endpoints
This section defines the target production contracts requested for next phase, plus mapping to current APIs.

### A. GET `/route-safe` (target)
Purpose:
- Return safest route between two points using candidate generation + risk scoring.

Input (query):
- `start_lat`, `start_lon`, `end_lat`, `end_lon`
- optional `alternatives`, `profile`, `at_time`

Output (example):
```json
{
  "selected_route": {
    "coordinates": [{"lat": 18.5204, "lon": 73.8567}],
    "summary": {
      "total_distance": 1234.5,
      "total_risk": 456.7,
      "average_safety_score": 71.4
    }
  },
  "alternatives": [
    {
      "summary": {
        "total_distance": 1300.1,
        "total_risk": 500.2,
        "average_safety_score": 68.0
      }
    }
  ]
}
```

Current related endpoints:
- `GET /api/v1/route` (mock)
- `POST /api/v1/route/risk` (implemented scorer for decoded coordinates)

### B. POST `/report` (target)
Purpose:
- Accept incident report from mobile and store in `incident_reports`.

Input (example):
```json
{
  "user_hash": "anon-user-123",
  "incident_type": "Poor lighting",
  "description": "Streetlight not working",
  "severity": 3,
  "lat": 18.5210,
  "lon": 73.8570
}
```

Output (example):
```json
{
  "id": "1e95f7f4-6e6d-4f79-b21d-62d4d6f87e9b",
  "status": "received",
  "message": "Thank you for your report."
}
```

Current related endpoint:
- `POST /api/v1/reports`

### C. GET `/safety-zones` (target)
Purpose:
- Return cached zone dataset for map overlay and offline sync.

Input:
- optional `bbox`, `zoom`, `version`

Output (example):
```json
{
  "dataset_version": "2026-03-12T09:00:00Z",
  "generated_at": "2026-03-12T09:00:00Z",
  "zones": [
    {
      "id": "zone_12",
      "lat": 18.523,
      "lon": 73.861,
      "radius_meters": 150,
      "classification": "cautious",
      "score": 58
    }
  ]
}
```

Current related endpoints:
- `GET /safety-map` and `GET /safety-score` in `logic/api.py` service (port 9123).

Migration recommendation:
1. Keep current endpoints for compatibility.
2. Add target endpoints with stable contracts.
3. Deprecate old paths after mobile clients migrate.
