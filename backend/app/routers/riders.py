from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query

from ..deps import conflict, get_conn, not_found
from ..schemas import (
    BikeIn,
    BikeOut,
    BikeStatsOut,
    CalibrationOut,
    RideOut,
    RiderIn,
    RiderOut,
)
from .rides import RIDE_COLUMNS

router = APIRouter(prefix="/v1", tags=["riders & bikes"])
Conn = Annotated[asyncpg.Connection, Depends(get_conn)]


@router.put("/riders/{rider_id}", response_model=RiderOut)
async def upsert_rider(rider_id: UUID, body: RiderIn, conn: Conn):
    row = await conn.fetchrow(
        """
        INSERT INTO riders (id, platform) VALUES ($1, $2)
        ON CONFLICT (id) DO UPDATE
            SET platform = EXCLUDED.platform, updated_at = now()
        RETURNING id, platform, created_at
        """,
        rider_id,
        body.platform,
    )
    return dict(row)


@router.get("/riders/{rider_id}", response_model=RiderOut)
async def get_rider(rider_id: UUID, conn: Conn):
    row = await conn.fetchrow(
        "SELECT id, platform, created_at FROM riders WHERE id = $1", rider_id
    )
    if row is None:
        raise not_found("Rider")
    return dict(row)


@router.put("/bikes/{bike_id}", response_model=BikeOut)
async def upsert_bike(bike_id: UUID, body: BikeIn, conn: Conn):
    if not await conn.fetchval("SELECT 1 FROM riders WHERE id = $1", body.rider_id):
        raise not_found("Rider")
    row = await conn.fetchrow(
        """
        INSERT INTO bikes (id, rider_id, model, rated_top_speed_kmh)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (id) DO UPDATE
            SET model = EXCLUDED.model,
                rated_top_speed_kmh = EXCLUDED.rated_top_speed_kmh,
                updated_at = now()
            WHERE bikes.rider_id = EXCLUDED.rider_id
        RETURNING id, rider_id, model, rated_top_speed_kmh, created_at
        """,
        bike_id,
        body.rider_id,
        body.model.strip(),
        body.rated_top_speed_kmh,
    )
    if row is None:
        raise conflict("Bike belongs to another rider")
    return dict(row)


@router.get("/bikes/{bike_id}", response_model=BikeOut)
async def get_bike(bike_id: UUID, conn: Conn):
    row = await conn.fetchrow(
        "SELECT id, rider_id, model, rated_top_speed_kmh, created_at "
        "FROM bikes WHERE id = $1",
        bike_id,
    )
    if row is None:
        raise not_found("Bike")
    return dict(row)


@router.get("/bikes/{bike_id}/rides", response_model=list[RideOut])
async def list_rides(
    bike_id: UUID,
    conn: Conn,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    kind: Annotated[str | None, Query(pattern="^(calibration|ride)$")] = None,
):
    rows = await conn.fetch(
        f"""
        SELECT {RIDE_COLUMNS},
               (SELECT count(*) FROM ride_samples s WHERE s.ride_id = r.id)
                   AS stored_sample_count
        FROM rides r
        WHERE r.bike_id = $1 AND ($2::text IS NULL OR r.kind = $2)
        ORDER BY r.started_at DESC
        LIMIT $3
        """,
        bike_id,
        kind,
        limit,
    )
    return [dict(r) for r in rows]


@router.get("/bikes/{bike_id}/stats", response_model=BikeStatsOut)
async def bike_stats(bike_id: UUID, conn: Conn):
    if not await conn.fetchval("SELECT 1 FROM bikes WHERE id = $1", bike_id):
        raise not_found("Bike")
    agg = await conn.fetchrow(
        """
        SELECT count(*)                          AS ride_count,
               coalesce(sum(distance_m), 0)      AS total_distance_m,
               max(max_speed_kmh)                AS max_speed_kmh,
               max(max_lean_left_deg)            AS max_lean_left_deg,
               max(max_lean_right_deg)           AS max_lean_right_deg,
               max(max_stop_time_s)              AS max_stop_time_s,
               max(best_decel_mps2)              AS best_decel_mps2
        FROM rides
        WHERE bike_id = $1 AND kind = 'ride' AND status = 'completed'
        """,
        bike_id,
    )
    cal = await conn.fetchrow(
        """
        SELECT * FROM calibrations WHERE bike_id = $1
        ORDER BY calibrated_at DESC LIMIT 1
        """,
        bike_id,
    )
    return {
        "bike_id": bike_id,
        **dict(agg),
        "latest_calibration": CalibrationOut(**dict(cal)) if cal else None,
    }
