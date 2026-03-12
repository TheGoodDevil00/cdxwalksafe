from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Mapping, Sequence, Set
import logging
import re

from app.database import database, settings
from app.schemas.reports import EmergencyAlertCreate, ReportCreate
from app.services.supabase_client import supabase_client

LOGGER = logging.getLogger(__name__)
_IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_EMERGENCY_FALLBACK_INCIDENT_TYPE = "__emergency_alert__"


class ReportingService:
    def __init__(self) -> None:
        self.base_confidence = 0.5
        self.incident_table = settings.SUPABASE_INCIDENT_TABLE
        self.emergency_table = settings.SUPABASE_EMERGENCY_TABLE
        self._table_columns_cache: Dict[str, Set[str]] = {}

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

        db_error: Exception | None = None
        if database.is_connected:
            try:
                return await self._insert_incident_report(payload)
            except Exception as exc:
                db_error = exc
                LOGGER.warning("Database incident insert failed, falling back to Supabase: %s", exc)

        if supabase_client.enabled:
            try:
                return await supabase_client.insert_row(
                    table=self.incident_table,
                    row=payload,
                )
            except Exception as exc:
                LOGGER.warning("Supabase incident insert failed: %s", exc)
                if db_error is not None:
                    raise db_error
                raise

        if db_error is not None:
            raise db_error
        raise RuntimeError("Database is unavailable and Supabase is not configured.")

    async def get_recent_reports(self, *, limit: int = 50) -> List[Dict[str, Any]]:
        select = (
            "id,latitude,longitude,incident_type,severity,confidence_score,created_at,status"
        )
        db_error: Exception | None = None
        if database.is_connected:
            try:
                rows = await self._fetch_recent_reports_via_db(limit=limit)
                return [_normalize_report_row(row) for row in rows]
            except Exception as exc:
                db_error = exc
                LOGGER.warning("Database recent reports fetch failed, falling back to Supabase: %s", exc)

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
                LOGGER.warning("Supabase recent reports fetch failed: %s", exc)
                if db_error is not None:
                    raise db_error
                return []

        if db_error is not None:
            raise db_error
        return []

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

        db_error: Exception | None = None
        if database.is_connected:
            try:
                return await self._insert_emergency_alert(payload)
            except Exception as exc:
                db_error = exc
                LOGGER.warning("Database emergency insert failed, falling back to Supabase: %s", exc)

        if supabase_client.enabled:
            try:
                return await supabase_client.insert_row(
                    table=self.emergency_table,
                    row=payload,
                )
            except Exception as exc:
                LOGGER.warning("Supabase emergency insert failed: %s", exc)
                if db_error is not None:
                    raise db_error
                raise

        if db_error is not None:
            raise db_error
        raise RuntimeError("Database is unavailable and Supabase is not configured.")

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
        db_error: Exception | None = None
        if database.is_connected:
            try:
                rows = await self._fetch_recent_incidents_via_db(
                    since=since,
                    limit=limit,
                )
                return [_normalize_incident_for_risk(row) for row in rows]
            except Exception as exc:
                db_error = exc
                LOGGER.warning("Database incident fetch for risk failed, falling back to Supabase: %s", exc)

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
                LOGGER.warning("Supabase incident fetch for risk failed: %s", exc)
                if db_error is not None:
                    raise db_error
                return []

        if db_error is not None:
            raise db_error
        return []

    async def _insert_incident_report(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        available_columns = await self._get_table_columns(self.incident_table)
        row = await self._insert_compatible_row(
            table=self.incident_table,
            available_columns=available_columns,
            payload=payload,
            required_columns={"incident_type", "latitude", "longitude"},
            returning_columns=("id", "status", "confidence_score", "created_at"),
        )
        row.setdefault("status", "received")
        row.setdefault("confidence_score", self.base_confidence)
        return row

    async def _insert_emergency_alert(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        available_columns = await self._get_table_columns(self.emergency_table)
        if available_columns:
            row = await self._insert_compatible_row(
                table=self.emergency_table,
                available_columns=available_columns,
                payload=payload,
                required_columns={"latitude", "longitude"},
                returning_columns=("id", "status", "created_at", "message"),
            )
            row.setdefault("status", "triggered")
            row.setdefault("message", payload.get("message"))
            return row

        LOGGER.warning(
            "Emergency table '%s' is unavailable; using incident report fallback.",
            self.emergency_table,
        )
        fallback_payload = {
            "user_hash": payload.get("user_hash"),
            "incident_type": _EMERGENCY_FALLBACK_INCIDENT_TYPE,
            "description": payload.get("message") or "Emergency alert triggered",
            "severity": 5,
            "status": "triggered",
            "confidence_score": 1.0,
            "latitude": payload.get("latitude"),
            "longitude": payload.get("longitude"),
            "metadata": {
                **(payload.get("metadata") or {}),
                "emergency_alert_fallback": True,
                "contacts_notified": payload.get("contacts_notified", 0),
            },
        }
        row = await self._insert_incident_report(fallback_payload)
        row["status"] = "triggered"
        row["message"] = payload.get("message") or "Emergency alert triggered"
        row.setdefault("created_at", datetime.now(timezone.utc))
        return row

    async def _fetch_recent_reports_via_db(self, *, limit: int) -> List[Dict[str, Any]]:
        available_columns = await self._get_table_columns(self.incident_table)
        if not available_columns:
            return []

        query, values = self._build_recent_incident_query(
            available_columns=available_columns,
            include_since=False,
        )
        values["limit"] = int(limit)
        rows = await database.fetch_all(query=query, values=values)
        return [dict(row) for row in rows]

    async def _fetch_recent_incidents_via_db(
        self,
        *,
        since: datetime,
        limit: int,
    ) -> List[Dict[str, Any]]:
        available_columns = await self._get_table_columns(self.incident_table)
        if not available_columns:
            return []

        query, values = self._build_recent_incident_query(
            available_columns=available_columns,
            include_since=False,
        )
        values["limit"] = int(limit)
        rows = await database.fetch_all(query=query, values=values)
        filtered_rows: List[Dict[str, Any]] = []
        for row in rows:
            row_dict = dict(row)
            created_at = _to_datetime(row_dict.get("created_at"))
            if created_at >= since:
                filtered_rows.append(row_dict)
        return filtered_rows

    async def _get_table_columns(self, table: str) -> Set[str]:
        _ensure_safe_identifier(table)
        cached = self._table_columns_cache.get(table)
        if cached is not None:
            return cached

        if not database.is_connected:
            return set()

        query = """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = :table_name
        ORDER BY ordinal_position
        """
        rows = await database.fetch_all(query=query, values={"table_name": table})
        columns = {
            str(row["column_name"])
            for row in rows
            if row["column_name"] is not None
        }
        self._table_columns_cache[table] = columns
        return columns

    async def _insert_compatible_row(
        self,
        *,
        table: str,
        available_columns: Set[str],
        payload: Mapping[str, Any],
        required_columns: Set[str],
        returning_columns: Sequence[str],
    ) -> Dict[str, Any]:
        _ensure_safe_identifier(table)
        if not available_columns:
            raise RuntimeError(f"Table '{table}' is unavailable.")

        missing_required = sorted(required_columns - available_columns)
        if missing_required:
            raise RuntimeError(
                f"Table '{table}' is missing required columns: {', '.join(missing_required)}"
            )

        insert_columns = [
            column
            for column in payload
            if column in available_columns
        ]
        if not insert_columns:
            raise RuntimeError(f"Table '{table}' has no compatible writable columns.")

        value_placeholders: List[str] = []
        values: Dict[str, Any] = {}
        for column in insert_columns:
            _ensure_safe_identifier(column)
            if column == "metadata":
                values[column] = _to_json_string(payload.get(column) or {})
                value_placeholders.append("CAST(:metadata AS jsonb)")
            else:
                values[column] = payload.get(column)
                value_placeholders.append(f":{column}")

        returning_exprs = [
            _returning_expression(column)
            for column in returning_columns
            if column in available_columns
        ]

        query = f"""
        INSERT INTO {table} ({", ".join(insert_columns)})
        VALUES ({", ".join(value_placeholders)})
        """
        if returning_exprs:
            query += f"\nRETURNING {', '.join(returning_exprs)}"

        row = await database.fetch_one(query=query, values=values)
        if row is None:
            raise RuntimeError(f"Insert into '{table}' returned no row.")
        return dict(row)

    def _build_recent_incident_query(
        self,
        *,
        available_columns: Set[str],
        include_since: bool,
    ) -> tuple[str, Dict[str, Any]]:
        id_expr = self._select_or_default(
            available_columns,
            "id",
            default="''",
            cast_to_text=True,
        )
        incident_type_expr = self._select_or_default(
            available_columns,
            "incident_type",
            default="'unknown'",
        )
        status_expr = self._select_or_default(
            available_columns,
            "status",
            default="'pending'",
        )
        select_columns = [
            f"{id_expr} AS id",
            f"{self._select_or_default(available_columns, 'latitude', default='0.0')} AS lat",
            f"{self._select_or_default(available_columns, 'longitude', default='0.0')} AS lon",
            f"{incident_type_expr} AS incident_type",
            f"{self._select_or_default(available_columns, 'severity', default='3')} AS severity",
            f"{self._select_or_default(available_columns, 'confidence_score', default='0.5')} AS confidence_score",
            f"{self._select_or_default(available_columns, 'created_at', default='NOW()')} AS created_at",
            f"{status_expr} AS status",
        ]

        filters: List[str] = []
        values: Dict[str, Any] = {}
        if "incident_type" in available_columns:
            filters.append("incident_type <> :emergency_fallback_type")
            values["emergency_fallback_type"] = _EMERGENCY_FALLBACK_INCIDENT_TYPE
        if include_since and "created_at" in available_columns:
            filters.append("created_at >= :since")

        where_clause = ""
        if filters:
            where_clause = "\nWHERE " + " AND ".join(filters)

        order_by = "created_at DESC" if "created_at" in available_columns else "id DESC"
        query = f"""
        SELECT
            {", ".join(select_columns)}
        FROM {self.incident_table}
        {where_clause}
        ORDER BY {order_by}
        LIMIT :limit
        """
        return query, values

    def _select_or_default(
        self,
        available_columns: Set[str],
        column: str,
        *,
        default: str,
        cast_to_text: bool = False,
    ) -> str:
        _ensure_safe_identifier(column)
        if column not in available_columns:
            return default
        if cast_to_text:
            return f"{column}::text"
        return column


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
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                return parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _to_iso8601(value: Any) -> str:
    return _to_datetime(value).isoformat()


def _to_json_string(payload: Dict[str, Any]) -> str:
    import json

    return json.dumps(payload)


def _ensure_safe_identifier(identifier: str) -> None:
    if not _IDENTIFIER_PATTERN.fullmatch(identifier):
        raise RuntimeError(f"Unsafe SQL identifier: {identifier}")


def _returning_expression(column: str) -> str:
    _ensure_safe_identifier(column)
    if column == "id":
        return "id::text AS id"
    return column


reporting_service = ReportingService()
