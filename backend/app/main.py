from contextlib import asynccontextmanager
import logging
import sys

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.session import AsyncSessionLocal
from app.routers import reports, routing
from app.services.safety_dataset_cache import safety_dataset_cache

LOGGER = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    if "pytest" not in sys.modules:
        try:
            async with AsyncSessionLocal() as session:
                await safety_dataset_cache.warm_cache(session)
        except Exception as exc:  # pragma: no cover - startup should degrade gracefully
            LOGGER.warning("Safety dataset cache warmup skipped: %s", exc)

    yield


app = FastAPI(
    title="WalkSafe API",
    description="Safety-aware pedestrian navigation API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(routing.router)
app.include_router(reports.router)


@app.get("/")
async def root():
    return {"message": "WalkSafe API is running", "status": "online"}
