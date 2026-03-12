from fastapi import FastAPI
from contextlib import asynccontextmanager
from app.database import database

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Connect to DB on startup
    try:
        await database.connect()
        print("Database connected")
    except Exception as e:
        print(f"Database connection failed: {e}")
        # We don't exit here to allow the app to run in 'offline' mode or for testing
    
    yield
    
    # Disconnect on shutdown
    await database.disconnect()

app = FastAPI(
    title="SafeWalk API",
    description="Safety-aware pedestrian navigation API",
    version="1.0.0",
    lifespan=lifespan
)

from app.routers import routing, reports
app.include_router(routing.router, prefix="/api/v1", tags=["routing"])
app.include_router(reports.router, prefix="/api/v1", tags=["reports"])

@app.get("/")
async def root():
    return {"message": "SafeWalk API is running", "status": "online"}
