from typing import Any, Dict, Optional
from datetime import datetime

from pydantic import BaseModel, Field


class ReportCreate(BaseModel):
    user_hash: str = Field(min_length=2, max_length=128)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    incident_type: str = Field(min_length=2, max_length=120)
    description: Optional[str] = None
    severity: int = Field(default=3, ge=1, le=5)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class ReportResponse(BaseModel):
    id: str
    status: str
    message: str


class RecentReport(BaseModel):
    id: str
    lat: float
    lon: float
    incident_type: str
    severity: int
    confidence_score: float
    created_at: datetime
    status: str


class EmergencyAlertCreate(BaseModel):
    user_hash: str = Field(min_length=2, max_length=128)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    message: Optional[str] = None
    contacts_notified: int = Field(default=0, ge=0)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class EmergencyAlertResponse(BaseModel):
    id: str
    status: str
    created_at: Optional[datetime] = None
    message: str
