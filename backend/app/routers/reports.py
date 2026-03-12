from typing import List

from fastapi import APIRouter, HTTPException

from app.schemas.reports import (
    EmergencyAlertCreate,
    EmergencyAlertResponse,
    RecentReport,
    ReportCreate,
    ReportResponse,
)
from app.services.reporting_service import reporting_service

router = APIRouter()


@router.post("/reports", response_model=ReportResponse)
@router.post("/report", response_model=ReportResponse)
async def submit_report(report: ReportCreate):
    try:
        created = await reporting_service.create_report(report)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Failed to persist report: {exc}")

    report_id = str(created.get("id", ""))
    status = str(created.get("status", "received"))
    return ReportResponse(
        id=report_id,
        status=status,
        message="Thank you for your report. It will be verified.",
    )


@router.get("/reports/recent", response_model=List[RecentReport])
async def get_recent_reports(limit: int = 50):
    bounded_limit = max(1, min(limit, 200))
    return await reporting_service.get_recent_reports(limit=bounded_limit)


@router.post("/reports/emergency", response_model=EmergencyAlertResponse)
@router.post("/report/emergency", response_model=EmergencyAlertResponse)
async def create_emergency_alert(alert: EmergencyAlertCreate):
    try:
        created = await reporting_service.create_emergency_alert(alert)
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to persist emergency alert: {exc}",
        )

    return EmergencyAlertResponse(
        id=str(created.get("id", "")),
        status=str(created.get("status", "triggered")),
        created_at=created.get("created_at"),
        message="Emergency alert has been triggered.",
    )
