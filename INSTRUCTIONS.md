# Coding Agent Instructions (Project Continuation)

## 1. Read Order
Read documents in this order before doing any implementation work:
1. `ROADMAP.md`
2. `BACKENDEXP.md`
3. `INSTRUCTIONS.md`

## 2. Planning Phase
Before making code changes, always complete this sequence:
1. Analyze current architecture and confirm active data flow paths.
2. Identify missing features and list blockers/dependencies.
3. Propose a step-by-step implementation plan with verification steps.

Hard rule:
- Do not begin coding until the plan is explicitly defined.

Expected planning output format:
1. Scope
2. Assumptions
3. Implementation steps
4. Validation steps
5. Rollback strategy

## 3. Development Strategy
Implement in this order:
1. Backend routing engine
2. Supabase integration
3. Risk scoring updates
4. Mobile integration

Why this order:
- Mobile depends on stable backend contracts.
- Risk scoring depends on incident persistence and queryability.
- Supabase schema consistency must be resolved before adding dynamic scoring logic.

## 4. Code Quality Requirements
All code must be:
- Modular and service-oriented.
- Well-documented with clear function boundaries.
- Consistent with existing repository architecture.

Rules:
- Avoid rewriting working components unless needed for compatibility.
- Prefer additive changes over broad refactors.
- Keep API contracts explicit and versioned where possible.
- Add defensive error handling for external APIs and network calls.
- Add tests for new business-critical logic (risk scoring and endpoint contracts).

## 5. Local Development Instructions
### A. Backend setup (FastAPI)
1. Open a terminal in project root.
2. Create virtual environment and install dependencies:
```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```
3. Start PostGIS locally:
```bash
docker compose up -d
```
4. Initialize schema:
```bash
python init_db.py
```
5. Run backend API:
```bash
uvicorn app.main:app --reload --port 8000
```
6. Verify:
- `GET http://127.0.0.1:8000/`
- `POST http://127.0.0.1:8000/api/v1/route/risk`

### B. Logic safety API setup (GeoJSON safety service)
1. In project root (or `logic/`), install logic dependencies:
```bash
cd logic
pip install -r requirements.txt
```
2. Ensure datasets exist (regenerate if needed):
```bash
cd ..
python logic/generate_safety_map.py
python logic/datagen.py
```
3. Run logic API:
```bash
uvicorn logic.api:app --reload --port 9123
```
4. Verify:
- `GET http://127.0.0.1:9123/`
- `GET http://127.0.0.1:9123/safety-score?lat=18.5204&lon=73.8567`

### C. Flutter app setup
1. Install dependencies:
```bash
cd mobile
flutter pub get
```
2. Run app with backend URLs:
```bash
flutter run \
  --dart-define=ROUTING_API_BASE_URL=http://127.0.0.1:8000/api/v1 \
  --dart-define=LOGIC_API_BASE_URL=http://127.0.0.1:9123
```

Android emulator note:
- Replace `127.0.0.1` with `10.0.2.2` for emulator-to-host networking.

## 6. Mobile App Deployment
Build commands:
```bash
cd mobile
flutter build apk --release
flutter build appbundle --release
```

Production backend configuration:
1. Provide production API host via `--dart-define` during build.
2. Remove hardcoded credentials/URLs from source and use environment-driven config.
3. Enable HTTPS-only endpoints for production.
4. Ensure CORS and auth policies align with deployed client domains/apps.

Recommended production build example:
```bash
flutter build appbundle --release \
  --dart-define=ROUTING_API_BASE_URL=https://api.example.com/api/v1 \
  --dart-define=LOGIC_API_BASE_URL=https://safety.example.com
```

## 7. Success Criteria
The system is considered complete when a user can:
1. Open the mobile app.
2. Select a destination.
3. Receive the safest route.
4. See safety zones on the map.
5. Report unsafe incidents.

Technical completion requirements:
- Routing engine uses live incident data in risk scoring.
- Incident reports persist in Supabase and are queryable by backend scoring jobs.
- Route response includes explainable safety summary.
- Mobile gracefully handles temporary backend outages with clear fallback behavior.

## Important Constraints
The agent must:
- Not modify existing working components unless required by active scope.
- Not restructure repository layout without explicit approval.
- Not delete files as part of feature work.
- Maintain backward compatibility when introducing new endpoints.
