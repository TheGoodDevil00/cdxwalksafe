from contextlib import asynccontextmanager
import logging
import os
import sys

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.db.session import AsyncSessionLocal
from app.routers.admin import router as admin_router
from app.routers import reports, routing
from app.services.safety_dataset_cache import safety_dataset_cache

LOGGER = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    skip_cache_warmup = os.environ.get("SKIP_CACHE_WARMUP", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }

    if "pytest" not in sys.modules and not skip_cache_warmup:
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
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*", "ngrok-skip-browser-warning"],
)


class NgrokHeaderMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["ngrok-skip-browser-warning"] = "true"
        return response


app.add_middleware(NgrokHeaderMiddleware)

app.include_router(admin_router)
app.include_router(routing.router)
app.include_router(reports.router)


@app.get("/")
async def root():
    return {"message": "WalkSafe API is running", "status": "online"}
