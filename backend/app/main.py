from fastapi import FastAPI

from app.routers import reports, routing

app = FastAPI(
    title="WalkSafe API",
    description="Safety-aware pedestrian navigation API",
    version="1.0.0",
)

app.include_router(routing.router)
app.include_router(reports.router)


@app.get("/")
async def root():
    return {"message": "WalkSafe API is running", "status": "online"}
