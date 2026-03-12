import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app.main import app


class ApiEndpointTests(unittest.TestCase):
    def test_route_risk_returns_segments_and_summary(self):
        mocked_payload = {
            "segments": [
                {
                    "start": {"lat": 18.52, "lon": 73.85},
                    "end": {"lat": 18.53, "lon": 73.86},
                    "risk": 12.5,
                }
            ],
            "summary": {
                "total_distance": 123.4,
                "total_risk": 12.5,
                "average_safety_score": 77.0,
                "applied_incident_count": 2,
            },
        }

        with patch(
            "app.routers.routing.risk_engine.score_route",
            new=AsyncMock(return_value=mocked_payload),
        ):
            with TestClient(app) as client:
                response = client.post(
                    "/api/v1/route/risk",
                    json={
                        "coordinates": [
                            {"lat": 18.52, "lon": 73.85},
                            {"lat": 18.53, "lon": 73.86},
                        ]
                    },
                )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["summary"]["total_risk"], 12.5)
        self.assertEqual(len(body["segments"]), 1)

    def test_route_safe_ranks_candidates_and_returns_meta(self):
        route_candidates = [
            {
                "distance": 1000.0,
                "duration": 720.0,
                "coordinates": [[73.85, 18.52], [73.86, 18.53]],
            },
            {
                "distance": 900.0,
                "duration": 650.0,
                "coordinates": [[73.85, 18.52], [73.855, 18.525]],
            },
        ]
        score_payloads = [
            {
                "segments": [{"risk": 80.0}],
                "summary": {
                    "total_distance": 1000.0,
                    "total_risk": 80.0,
                    "average_safety_score": 55.0,
                    "applied_incident_count": 4,
                },
            },
            {
                "segments": [{"risk": 20.0}],
                "summary": {
                    "total_distance": 900.0,
                    "total_risk": 20.0,
                    "average_safety_score": 82.0,
                    "applied_incident_count": 4,
                },
            },
        ]

        with patch(
            "app.routers.routing.osrm_service.fetch_walking_routes",
            new=AsyncMock(return_value=route_candidates),
        ), patch(
            "app.routers.routing.risk_engine.score_route",
            new=AsyncMock(side_effect=score_payloads),
        ):
            with TestClient(app) as client:
                response = client.get(
                    "/api/v1/route-safe",
                    params={
                        "start_lat": 18.52,
                        "start_lon": 73.85,
                        "end_lat": 18.53,
                        "end_lon": 73.86,
                        "alternatives": 2,
                    },
                )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["selected_route"]["summary"]["total_risk"], 20.0)
        self.assertEqual(body["alternatives"][0]["summary"]["total_risk"], 80.0)
        self.assertEqual(body["meta"]["source"], "osrm+risk_engine")

    def test_safety_zones_returns_not_modified_when_version_matches(self):
        mocked_payload = {
            "dataset_version": "2026-03-12T18:30:00Z",
            "generated_at": "2026-03-12T18:30:00Z",
            "valid_until": "2026-03-12T18:45:00Z",
            "zones": [{"id": "zone_1", "lat": 18.52, "lon": 73.85}],
            "geojson": {"type": "FeatureCollection", "features": [{"type": "Feature"}]},
        }

        with patch(
            "app.routers.routing.safety_zone_service.get_safety_zones",
            new=AsyncMock(return_value=mocked_payload),
        ):
            with TestClient(app) as client:
                response = client.get(
                    "/api/v1/safety-zones",
                    params={"version": "2026-03-12T18:30:00Z"},
                )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["not_modified"])
        self.assertEqual(body["zones"], [])

    def test_report_alias_returns_response_contract(self):
        with patch(
            "app.routers.reports.reporting_service.create_report",
            new=AsyncMock(return_value={"id": "report-1", "status": "received"}),
        ):
            with TestClient(app) as client:
                response = client.post(
                    "/api/v1/report",
                    json={
                        "user_hash": "user-1",
                        "incident_type": "Poor lighting",
                        "severity": 3,
                        "lat": 18.52,
                        "lon": 73.85,
                        "description": "Dark segment",
                        "metadata": {},
                    },
                )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "id": "report-1",
                "status": "received",
                "message": "Thank you for your report. It will be verified.",
            },
        )

    def test_report_emergency_alias_returns_response_contract(self):
        with patch(
            "app.routers.reports.reporting_service.create_emergency_alert",
            new=AsyncMock(
                return_value={
                    "id": "emergency-1",
                    "status": "triggered",
                    "created_at": "2026-03-12T18:30:00Z",
                }
            ),
        ):
            with TestClient(app) as client:
                response = client.post(
                    "/api/v1/report/emergency",
                    json={
                        "user_hash": "user-1",
                        "lat": 18.52,
                        "lon": 73.85,
                        "message": "Help needed",
                        "contacts_notified": 0,
                        "metadata": {},
                    },
                )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["id"], "emergency-1")
        self.assertEqual(body["status"], "triggered")
        self.assertEqual(body["message"], "Emergency alert has been triggered.")


if __name__ == "__main__":
    unittest.main()
