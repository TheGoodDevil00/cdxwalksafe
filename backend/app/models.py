from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class Node(BaseModel):
    id: int
    lat: float
    lon: float

class Edge(BaseModel):
    id: int
    source: int
    target: int
    risk_score: float
    distance: float

class Incident(BaseModel):
    id: Optional[int] = None
    lat: float
    lon: float
    type: str
    severity: int
    description: Optional[str] = None
    reported_at: datetime = datetime.now()
