from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
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
async def submit_report(
    report: ReportCreate,
    db: AsyncSession = Depends(get_db),
):
    try:
        created = await reporting_service.create_report(report, db)
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to persist report: {exc}",
        ) from exc

    report_id = str(created.get("id", ""))
    status = str(created.get("status", "pending"))
    return ReportResponse(
        id=report_id,
        status=status,
        message="Thank you for your report. It will be verified.",
    )


@router.get("/reports/recent", response_model=List[RecentReport])
async def get_recent_reports(
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
):
    bounded_limit = max(1, min(limit, 200))
    return await reporting_service.get_recent_reports(limit=bounded_limit, db=db)


@router.post("/reports/emergency", response_model=EmergencyAlertResponse)
@router.post("/report/emergency", response_model=EmergencyAlertResponse)
async def create_emergency_alert(
    alert: EmergencyAlertCreate,
    db: AsyncSession = Depends(get_db),
):
    try:
        created = await reporting_service.create_emergency_alert(alert, db)
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to persist emergency alert: {exc}",
        ) from exc

    return EmergencyAlertResponse(
        id=str(created.get("id", "")),
        status=str(created.get("status", "pending")),
        created_at=created.get("created_at"),
        message=str(created.get("message", "Emergency alert has been recorded.")),
        contacts_notified=int(created.get("contacts_notified", 0)),
        trusted_contacts=[
            str(contact)
            for contact in (created.get("trusted_contacts") or [])
            if contact is not None
        ],
    )
