from typing import Any, Dict, List

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.reports import EmergencyAlertCreate, ReportCreate


class ReportingService:
    def __init__(self) -> None:
        self.base_confidence = 0.5

    async def create_report(
        self,
        report: ReportCreate,
        db: AsyncSession,
    ) -> Dict[str, Any]:
        result = await db.execute(
            text(
                """
                INSERT INTO incident_reports (
                    user_hash,
                    category,
                    description,
                    location,
                    status,
                    confidence
                )
                VALUES (
                    :user_hash,
                    :category,
                    :description,
                    ST_SetSRID(ST_MakePoint(:lon, :lat), 4326),
                    'pending',
                    :confidence
                )
                RETURNING id::text AS id, status, confidence, submitted_at
                """
            ),
            {
                "user_hash": report.user_hash,
                "category": report.category,
                "description": report.description,
                "lon": report.lon,
                "lat": report.lat,
                "confidence": self.base_confidence,
            },
        )
        row = result.fetchone()
        if row is None:
            raise RuntimeError("Incident report insert returned no row.")
        return dict(row._mapping)

    async def get_recent_reports(
        self,
        *,
        limit: int,
        db: AsyncSession,
    ) -> List[Dict[str, Any]]:
        result = await db.execute(
            text(
                """
                SELECT
                    id::text AS id,
                    ST_Y(location) AS lat,
                    ST_X(location) AS lon,
                    category AS incident_type,
                    3 AS severity,
                    confidence AS confidence_score,
                    submitted_at AS created_at,
                    status
                FROM incident_reports
                ORDER BY submitted_at DESC
                LIMIT :limit
                """
            ),
            {"limit": int(limit)},
        )
        rows = result.fetchall()
        return [dict(row._mapping) for row in rows]

    async def create_emergency_alert(
        self,
        alert: EmergencyAlertCreate,
        db: AsyncSession,
    ) -> Dict[str, Any]:
        result = await db.execute(
            text(
                """
                INSERT INTO incident_reports (
                    user_hash,
                    category,
                    description,
                    location,
                    status,
                    confidence
                )
                VALUES (
                    :user_hash,
                    'emergency_alert',
                    :description,
                    ST_SetSRID(ST_MakePoint(:lon, :lat), 4326),
                    'pending',
                    1.0
                )
                RETURNING id::text AS id, status, submitted_at
                """
            ),
            {
                "user_hash": alert.user_hash,
                "description": alert.message or "Emergency alert triggered",
                "lon": alert.lon,
                "lat": alert.lat,
            },
        )
        row = result.fetchone()
        if row is None:
            raise RuntimeError("Emergency alert insert returned no row.")
        payload = dict(row._mapping)
        payload["message"] = alert.message or "Emergency alert triggered"
        return payload


reporting_service = ReportingService()
