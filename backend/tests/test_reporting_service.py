import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import patch

from app.schemas.reports import EmergencyAlertCreate, ReportCreate
from app.services import reporting_service as reporting_module


class FakeDatabase:
    def __init__(self, *, columns_by_table, fetch_one_result=None, fetch_all_rows=None):
        self.is_connected = True
        self.columns_by_table = columns_by_table
        self.fetch_one_result = fetch_one_result or {}
        self.fetch_all_rows = fetch_all_rows or []
        self.calls = []

    async def fetch_all(self, query, values=None):
        self.calls.append(("fetch_all", query, values))
        if "information_schema.columns" in query:
            table = (values or {}).get("table_name")
            columns = self.columns_by_table.get(table, set())
            return [{"column_name": column} for column in columns]
        return list(self.fetch_all_rows)

    async def fetch_one(self, query, values=None):
        self.calls.append(("fetch_one", query, values))
        return dict(self.fetch_one_result)


class ReportingServiceCompatibilityTests(unittest.IsolatedAsyncioTestCase):
    async def test_create_report_uses_legacy_incident_schema_columns(self):
        fake_db = FakeDatabase(
            columns_by_table={
                "incident_reports": {
                    "id",
                    "incident_type",
                    "description",
                    "latitude",
                    "longitude",
                    "created_at",
                }
            },
            fetch_one_result={
                "id": "legacy-report-1",
                "created_at": datetime(2026, 3, 12, tzinfo=timezone.utc),
            },
        )
        fake_supabase = SimpleNamespace(enabled=False)

        with patch.object(reporting_module, "database", fake_db), patch.object(
            reporting_module, "supabase_client", fake_supabase
        ):
            service = reporting_module.ReportingService()
            created = await service.create_report(
                ReportCreate(
                    user_hash="user-123",
                    incident_type="Poor lighting",
                    severity=3,
                    lat=18.52,
                    lon=73.85,
                    description="Dark stretch",
                    metadata={"source": "test"},
                )
            )

        insert_call = next(call for call in fake_db.calls if call[0] == "fetch_one")
        query = insert_call[1]
        values = insert_call[2]
        self.assertIn("INSERT INTO incident_reports", query)
        self.assertIn("incident_type", query)
        self.assertIn("latitude", query)
        self.assertIn("longitude", query)
        self.assertNotIn("user_hash", query)
        self.assertNotIn("severity", query)
        self.assertEqual(values["incident_type"], "Poor lighting")
        self.assertEqual(created["id"], "legacy-report-1")
        self.assertEqual(created["status"], "received")

    async def test_recent_reports_supply_defaults_and_exclude_emergency_fallback_rows(self):
        fake_db = FakeDatabase(
            columns_by_table={
                "incident_reports": {
                    "id",
                    "incident_type",
                    "description",
                    "latitude",
                    "longitude",
                    "created_at",
                }
            },
            fetch_all_rows=[
                {
                    "id": "legacy-report-2",
                    "lat": 18.52,
                    "lon": 73.85,
                    "incident_type": "Poor lighting",
                    "severity": 3,
                    "confidence_score": 0.5,
                    "created_at": datetime(2026, 3, 12, tzinfo=timezone.utc),
                    "status": "pending",
                }
            ],
        )
        fake_supabase = SimpleNamespace(enabled=False)

        with patch.object(reporting_module, "database", fake_db), patch.object(
            reporting_module, "supabase_client", fake_supabase
        ):
            service = reporting_module.ReportingService()
            reports = await service.get_recent_reports(limit=5)

        select_call = fake_db.calls[-1]
        query = select_call[1]
        values = select_call[2]
        self.assertIn("incident_type <> :emergency_fallback_type", query)
        self.assertEqual(
            values["emergency_fallback_type"],
            reporting_module._EMERGENCY_FALLBACK_INCIDENT_TYPE,
        )
        self.assertEqual(len(reports), 1)
        self.assertEqual(reports[0]["severity"], 3)
        self.assertEqual(reports[0]["confidence_score"], 0.5)
        self.assertEqual(reports[0]["status"], "pending")

    async def test_emergency_alert_falls_back_to_incident_reports_when_table_missing(self):
        fake_db = FakeDatabase(
            columns_by_table={
                "incident_reports": {
                    "id",
                    "incident_type",
                    "description",
                    "latitude",
                    "longitude",
                    "created_at",
                },
                "emergency_alerts": set(),
            },
            fetch_one_result={
                "id": "legacy-emergency-1",
                "created_at": datetime(2026, 3, 12, tzinfo=timezone.utc),
            },
        )
        fake_supabase = SimpleNamespace(enabled=False)

        with patch.object(reporting_module, "database", fake_db), patch.object(
            reporting_module, "supabase_client", fake_supabase
        ):
            service = reporting_module.ReportingService()
            created = await service.create_emergency_alert(
                EmergencyAlertCreate(
                    user_hash="user-999",
                    lat=18.52,
                    lon=73.85,
                    message="Need help",
                    contacts_notified=0,
                    metadata={"source": "test"},
                )
            )

        insert_call = next(call for call in fake_db.calls if call[0] == "fetch_one")
        query = insert_call[1]
        values = insert_call[2]
        self.assertIn("INSERT INTO incident_reports", query)
        self.assertEqual(
            values["incident_type"],
            reporting_module._EMERGENCY_FALLBACK_INCIDENT_TYPE,
        )
        self.assertEqual(created["id"], "legacy-emergency-1")
        self.assertEqual(created["status"], "triggered")
        self.assertEqual(created["message"], "Need help")


if __name__ == "__main__":
    unittest.main()
