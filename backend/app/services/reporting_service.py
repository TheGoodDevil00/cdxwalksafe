from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List
import logging

from app.database import database, settings
from app.schemas.reports import EmergencyAlertCreate, ReportCreate
from app.services.supabase_client import supabase_client

LOGGER = logging.getLogger(__name__)


class ReportingService:
    def __init__(self) -> None:
        self.base_confidence = 0.5
        self.incident_table = settings.SUPABASE_INCIDENT_TABLE
        self.emergency_table = settings.SUPABASE_EMERGENCY_TABLE

    async def create_report(self, report: ReportCreate) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "user_hash": report.user_hash,
            "incident_type": report.incident_type,
            "description": report.description or None,
            "severity": report.severity,
            "status": "pending",
            "confidence_score": self.base_confidence,
            "latitude": report.lat,
            "longitude": report.lon,
            "metadata": report.metadata or {},
        }

        if supabase_client.enabled:
            try:
                return await supabase_client.insert_row(
                    table=self.incident_table,
                    row=payload,
                )
            except Exception as exc:
                LOGGER.warning(
                    "Supabase incident insert failed, falling back to DB: %s", exc
                )

        if not database.is_connected:
            raise RuntimeError(
                "Database is unavailable and Supabase is not configured."
            )

        query = """
        INSERT INTO incident_reports (
            user_hash,
            incident_type,
            description,
            severity,
            status,
            confidence_score,
            latitude,
            longitude,
            metadata
        )
        VALUES (
            :user_hash,
            :incident_type,
            :description,
            :severity,
            :status,
            :confidence_score,
            :latitude,
            :longitude,
            CAST(:metadata AS jsonb)
        )
        RETURNING id, status, confidence_score, created_at
        """
        values = {
            **payload,
            "metadata": _to_json_string(payload.get("metadata", {})),
        }
        row = await database.fetch_one(query=query, values=values)
        if row is None:
            raise RuntimeError("Incident report insert returned no row.")
        return dict(row)

    async def get_recent_reports(self, *, limit: int = 50) -> List[Dict[str, Any]]:
        select = (
            "id,latitude,longitude,incident_type,severity,confidence_score,created_at,status"
        )
        if supabase_client.enabled:
            try:
                rows = await supabase_client.fetch_rows(
                    table=self.incident_table,
                    select=select,
                    order="created_at.desc",
                    limit=limit,
                )
                return [_normalize_report_row(row) for row in rows]
            except Exception as exc:
                LOGGER.warning(
                    "Supabase recent reports fetch failed, falling back to DB: %s", exc
                )

        if not database.is_connected:
            return []

        query = """
        SELECT
            id::text AS id,
            latitude AS lat,
            longitude AS lon,
            incident_type,
            severity,
            confidence_score,
            created_at,
            status
        FROM incident_reports
        ORDER BY created_at DESC
        LIMIT :limit
        """
        rows = await database.fetch_all(query=query, values={"limit": int(limit)})
        return [_normalize_report_row(dict(row)) for row in rows]

    async def create_emergency_alert(
        self,
        alert: EmergencyAlertCreate,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "user_hash": alert.user_hash,
            "latitude": alert.lat,
            "longitude": alert.lon,
            "status": "triggered",
            "message": alert.message or "Emergency alert triggered",
            "contacts_notified": alert.contacts_notified,
            "metadata": alert.metadata or {},
        }

        if supabase_client.enabled:
            try:
                return await supabase_client.insert_row(
                    table=self.emergency_table,
                    row=payload,
                )
            except Exception as exc:
                LOGGER.warning(
                    "Supabase emergency insert failed, falling back to DB: %s", exc
                )

        if not database.is_connected:
            raise RuntimeError(
                "Database is unavailable and Supabase is not configured."
            )

        query = """
        INSERT INTO emergency_alerts (
            user_hash,
            latitude,
            longitude,
            status,
            message,
            contacts_notified,
            metadata
        )
        VALUES (
            :user_hash,
            :latitude,
            :longitude,
            :status,
            :message,
            :contacts_notified,
            CAST(:metadata AS jsonb)
        )
        RETURNING id, status, created_at, message
        """
        values = {
            **payload,
            "metadata": _to_json_string(payload.get("metadata", {})),
        }
        row = await database.fetch_one(query=query, values=values)
        if row is None:
            raise RuntimeError("Emergency alert insert returned no row.")
        return dict(row)

    async def get_recent_incidents(
        self,
        *,
        lookback_days: int = 30,
        limit: int = 5000,
    ) -> List[Dict[str, Any]]:
        since = datetime.now(timezone.utc) - timedelta(days=max(1, lookback_days))
        since_iso = since.isoformat()

        select = (
            "id,latitude,longitude,incident_type,severity,confidence_score,created_at,status"
        )
        if supabase_client.enabled:
            try:
                rows = await supabase_client.fetch_rows(
                    table=self.incident_table,
                    select=select,
                    filters={
                        "created_at": f"gte.{since_iso}",
                    },
                    order="created_at.desc",
                    limit=limit,
                )
                return [_normalize_incident_for_risk(row) for row in rows]
            except Exception as exc:
                LOGGER.warning(
                    "Supabase incident fetch for risk failed, falling back to DB: %s", exc
                )

        if not database.is_connected:
            return []

        query = """
        SELECT
            id::text AS id,
            latitude,
            longitude,
            incident_type,
            severity,
            confidence_score,
            created_at,
            status
        FROM incident_reports
        WHERE created_at >= :since
        ORDER BY created_at DESC
        LIMIT :limit
        """
        rows = await database.fetch_all(
            query=query,
            values={"since": since, "limit": int(limit)},
        )
        return [_normalize_incident_for_risk(dict(row)) for row in rows]


def _normalize_report_row(row: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": str(row.get("id", "")),
        "lat": _as_float(row.get("lat", row.get("latitude")), 0.0),
        "lon": _as_float(row.get("lon", row.get("longitude")), 0.0),
        "incident_type": str(row.get("incident_type", "unknown")),
        "severity": int(row.get("severity", 3) or 3),
        "confidence_score": _as_float(row.get("confidence_score"), 0.5),
        "created_at": _to_iso8601(row.get("created_at")),
        "status": str(row.get("status", "pending")),
    }


def _normalize_incident_for_risk(row: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": str(row.get("id", "")),
        "lat": _as_float(row.get("lat", row.get("latitude")), 0.0),
        "lon": _as_float(row.get("lon", row.get("longitude")), 0.0),
        "incident_type": str(row.get("incident_type", "unknown")),
        "severity": int(row.get("severity", 3) or 3),
        "confidence_score": _as_float(row.get("confidence_score"), 0.5),
        "created_at": _to_datetime(row.get("created_at")),
        "status": str(row.get("status", "pending")),
    }


def _as_float(value: Any, default: float) -> float:
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def _to_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _to_iso8601(value: Any) -> str:
    return _to_datetime(value).isoformat()


def _to_json_string(payload: Dict[str, Any]) -> str:
    import json

    return json.dumps(payload)


reporting_service = ReportingService()
