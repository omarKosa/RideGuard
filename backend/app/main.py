import logging
import os
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .catalogue_sync import sync_catalogue
from .db import create_pool, migrate
from .routers import calibrations, incidents, model_checks, riders, rides

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))


def create_app(database_url: str | None = None) -> FastAPI:
    """App factory (run with `uvicorn app.main:create_app --factory`)."""
    dsn = database_url or os.environ["DATABASE_URL"]

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.pool = await create_pool(dsn)
        await migrate(app.state.pool)
        await sync_catalogue(app.state.pool)
        try:
            yield
        finally:
            await app.state.pool.close()

    app = FastAPI(
        title="RideGuard API",
        version="2.0.0",
        description="Stores calibrated motorcycle ride data: lean angle, "
        "speed, braking and the phone-mount calibration behind them.",
        lifespan=lifespan,
    )
    app.include_router(riders.router)
    app.include_router(rides.router)
    app.include_router(calibrations.router)
    app.include_router(incidents.router)
    app.include_router(model_checks.router)

    @app.get("/health", tags=["ops"])
    async def health(request: Request):
        try:
            async with request.app.state.pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
        except (OSError, asyncpg.PostgresError) as exc:
            return JSONResponse(
                status_code=503,
                content={"status": "degraded", "database": str(exc)},
            )
        return {"status": "ok", "database": "ok"}

    # Last line of defence: Pydantic validation should catch bad data first,
    # but the database constraints are authoritative.
    @app.exception_handler(asyncpg.CheckViolationError)
    async def check_violation(_: Request, exc: asyncpg.CheckViolationError):
        return JSONResponse(
            status_code=422,
            content={"detail": f"Rejected by database constraint: {exc.constraint_name}"},
        )

    @app.exception_handler(asyncpg.ForeignKeyViolationError)
    async def fk_violation(_: Request, exc: asyncpg.ForeignKeyViolationError):
        return JSONResponse(
            status_code=404,
            content={"detail": f"Referenced record not found ({exc.constraint_name})"},
        )

    return app
