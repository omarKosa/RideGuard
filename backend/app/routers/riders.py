import logging
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.concurrency import run_in_threadpool

from ..deps import conflict, get_conn, not_found
from ..google_auth import GoogleNotConfigured, InvalidGoogleToken
from ..schemas import (
    BikeIn,
    BikeOut,
    BikeStatsOut,
    CalibrationOut,
    GoogleLinkIn,
    RideOut,
    RiderIn,
    RiderNameIn,
    RiderOut,
)
from .rides import RIDE_COLUMNS

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["riders & bikes"])
BIKE_COLUMNS = (
    "id, rider_id, model, rated_top_speed_kmh, catalogue_model_id, "
    "catalogue_version, other_make, other_model, other_year, "
    "top_speed_source, created_at"
)
RIDER_COLUMNS = (
    "id, platform, phone_model, os_version, google_email, google_name, "
    "display_name, created_at"
)
Conn = Annotated[asyncpg.Connection, Depends(get_conn)]


@router.put("/riders/{rider_id}", response_model=RiderOut)
async def upsert_rider(rider_id: UUID, body: RiderIn, conn: Conn):
    row = await conn.fetchrow(
        f"""
        INSERT INTO riders (id, platform, phone_model, os_version)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (id) DO UPDATE
            SET platform = EXCLUDED.platform,
                phone_model = EXCLUDED.phone_model,
                os_version = EXCLUDED.os_version,
                updated_at = now()
        RETURNING {RIDER_COLUMNS}
        """,
        rider_id,
        body.platform,
        body.phone_model,
        body.os_version,
    )
    return dict(row)


@router.get("/riders/{rider_id}", response_model=RiderOut)
async def get_rider(rider_id: UUID, conn: Conn):
    row = await conn.fetchrow(
        f"SELECT {RIDER_COLUMNS} FROM riders WHERE id = $1", rider_id
    )
    if row is None:
        raise not_found("Rider")
    return dict(row)


@router.put("/riders/{rider_id}/name", response_model=RiderOut)
async def set_rider_name(rider_id: UUID, body: RiderNameIn, conn: Conn):
    """Sets the name the rider chose. Idempotent (last write wins), so the
    app's outbox can retry it from any network address."""
    row = await conn.fetchrow(
        f"""
        UPDATE riders SET display_name = $2, updated_at = now()
        WHERE id = $1
        RETURNING {RIDER_COLUMNS}
        """,
        rider_id,
        body.name,
    )
    if row is None:
        raise not_found("Rider")
    return dict(row)


@router.put("/riders/{rider_id}/google", response_model=RiderOut)
async def link_google(
    rider_id: UUID, body: GoogleLinkIn, request: Request, conn: Conn
):
    """Links the Google account the phone signed in with to this rider.
    The token is verified with Google; an account already linked to another
    rider (an earlier install) moves to this one."""
    verify = request.app.state.verify_google
    try:
        identity = await run_in_threadpool(verify, body.id_token)
    except GoogleNotConfigured:
        raise HTTPException(503, "Google sign-in is not configured on the server")
    except InvalidGoogleToken as exc:
        logger.warning("Google token rejected: %s", exc)
        raise HTTPException(401, "Invalid Google sign-in token")
    async with conn.transaction():
        if not await conn.fetchval("SELECT 1 FROM riders WHERE id = $1", rider_id):
            raise not_found("Rider")
        await conn.execute(
            """
            UPDATE riders SET google_sub = NULL, google_email = NULL,
                google_name = NULL, google_linked_at = NULL, updated_at = now()
            WHERE google_sub = $1 AND id <> $2
            """,
            identity.sub,
            rider_id,
        )
        row = await conn.fetchrow(
            f"""
            UPDATE riders SET google_sub = $2, google_email = $3,
                google_name = $4, google_linked_at = now(), updated_at = now()
            WHERE id = $1
            RETURNING {RIDER_COLUMNS}
            """,
            rider_id,
            identity.sub,
            identity.email,
            (identity.name or None) and identity.name[:120],
        )
    return dict(row)


@router.put("/bikes/{bike_id}", response_model=BikeOut)
async def upsert_bike(bike_id: UUID, body: BikeIn, conn: Conn):
    if not await conn.fetchval("SELECT 1 FROM riders WHERE id = $1", body.rider_id):
        raise not_found("Rider")
    row = await conn.fetchrow(
        f"""
        INSERT INTO bikes (id, rider_id, model, rated_top_speed_kmh,
                           catalogue_model_id, catalogue_version, other_make,
                           other_model, other_year, top_speed_source)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (id) DO UPDATE
            SET model = EXCLUDED.model,
                rated_top_speed_kmh = EXCLUDED.rated_top_speed_kmh,
                catalogue_model_id = EXCLUDED.catalogue_model_id,
                catalogue_version = EXCLUDED.catalogue_version,
                other_make = EXCLUDED.other_make,
                other_model = EXCLUDED.other_model,
                other_year = EXCLUDED.other_year,
                top_speed_source = EXCLUDED.top_speed_source,
                updated_at = now()
            WHERE bikes.rider_id = EXCLUDED.rider_id
        RETURNING {BIKE_COLUMNS}
        """,
        bike_id,
        body.rider_id,
        body.model.strip(),
        body.rated_top_speed_kmh,
        body.catalogue_model_id,
        body.catalogue_version,
        body.other_make,
        body.other_model,
        body.other_year,
        body.top_speed_source,
    )
    if row is None:
        raise conflict("Bike belongs to another rider")
    return dict(row)


@router.get("/bikes/{bike_id}", response_model=BikeOut)
async def get_bike(bike_id: UUID, conn: Conn):
    row = await conn.fetchrow(
        f"SELECT {BIKE_COLUMNS} FROM bikes WHERE id = $1",
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
