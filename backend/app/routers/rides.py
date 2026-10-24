from datetime import datetime, timedelta, timezone
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query

from ..deps import conflict, get_conn, not_found, unprocessable
from ..schemas import (
    RideIn,
    RideOut,
    RideSummaryIn,
    SampleBatchIn,
    SampleBatchOut,
    WindowAnalysisOut,
)

router = APIRouter(prefix="/v1/rides", tags=["rides"])
Conn = Annotated[asyncpg.Connection, Depends(get_conn)]

RIDE_COLUMNS = """
    r.id, r.bike_id, r.calibration_id, r.kind, r.status, r.started_at,
    r.ended_at, r.analysis_window_min, r.mount_realignments,
    r.reported_sample_count, r.max_speed_kmh, r.max_lean_left_deg,
    r.max_lean_right_deg, r.max_stop_time_s, r.best_decel_mps2,
    r.brake_event_count, r.distance_m, r.moving_time_s,
    r.avg_moving_speed_kmh, r.window_stats, r.safety_stats,
    r.performance
"""

# Phone and server clocks differ; allow this much slack on timestamps.
CLOCK_SKEW = timedelta(minutes=5)


@router.put("/{ride_id}", response_model=RideOut)
async def upsert_ride(ride_id: UUID, body: RideIn, conn: Conn):
    if body.started_at > datetime.now(timezone.utc) + CLOCK_SKEW:
        raise unprocessable("started_at is in the future")
    if not await conn.fetchval("SELECT 1 FROM bikes WHERE id = $1", body.bike_id):
        raise not_found("Bike")
    if body.calibration_id is not None:
        cal_bike = await conn.fetchval(
            "SELECT bike_id FROM calibrations WHERE id = $1", body.calibration_id
        )
        if cal_bike is None:
            raise not_found("Calibration")
        if cal_bike != body.bike_id:
            raise unprocessable("Calibration belongs to a different bike")

    row = await conn.fetchrow(
        """
        INSERT INTO rides (id, bike_id, calibration_id, kind, started_at,
                           analysis_window_min)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (id) DO UPDATE
            SET started_at = EXCLUDED.started_at,
                calibration_id = EXCLUDED.calibration_id,
                analysis_window_min = EXCLUDED.analysis_window_min,
                updated_at = now()
            -- A retried header must not move a ride to another bike or
            -- reopen a finished one.
            WHERE rides.bike_id = EXCLUDED.bike_id AND rides.kind = EXCLUDED.kind
        RETURNING id
        """,
        ride_id,
        body.bike_id,
        body.calibration_id,
        body.kind,
        body.started_at,
        body.analysis_window_min,
    )
    if row is None:
        raise conflict("Ride already exists with a different bike or kind")
    return await _load_ride(conn, ride_id)


@router.post("/{ride_id}/samples", response_model=SampleBatchOut)
async def add_samples(ride_id: UUID, body: SampleBatchIn, conn: Conn):
    started_at = await conn.fetchval(
        "SELECT started_at FROM rides WHERE id = $1", ride_id
    )
    if started_at is None:
        raise not_found("Ride")

    latest_allowed = datetime.now(timezone.utc) + CLOCK_SKEW
    for s in body.samples:
        if s.recorded_at < started_at - CLOCK_SKEW or s.recorded_at > latest_allowed:
            raise unprocessable(
                f"Sample {s.seq} recorded_at {s.recorded_at.isoformat()} is "
                "outside the ride's time range"
            )

    cols = list(zip(*(
        (
            s.seq, s.recorded_at, s.speed_kmh, s.speed_source, s.lean_deg,
            s.roll_rate_dps, s.yaw_rate_dps, s.forward_accel_mps2,
            s.lateral_accel_mps2, s.latitude, s.longitude, s.gps_accuracy_m,
        )
        for s in body.samples
    )))
    # One round trip for the whole batch; (ride_id, seq) dedupes retries.
    inserted = await conn.fetchval(
        """
        WITH ins AS (
            INSERT INTO ride_samples (
                ride_id, seq, recorded_at, speed_kmh, speed_source, lean_deg,
                roll_rate_dps, yaw_rate_dps, forward_accel_mps2,
                lateral_accel_mps2, latitude, longitude, gps_accuracy_m)
            SELECT $1, * FROM unnest(
                $2::int[], $3::timestamptz[], $4::real[], $5::text[],
                $6::real[], $7::real[], $8::real[], $9::real[], $10::real[],
                $11::float8[], $12::float8[], $13::real[])
            ON CONFLICT (ride_id, seq) DO NOTHING
            RETURNING 1
        )
        SELECT count(*) FROM ins
        """,
        ride_id,
        *cols,
    )
    received = len(body.samples)
    return {"received": received, "inserted": inserted, "duplicates": received - inserted}


@router.put("/{ride_id}/summary", response_model=RideOut)
async def finish_ride(ride_id: UUID, body: RideSummaryIn, conn: Conn):
    started_at = await conn.fetchval(
        "SELECT started_at FROM rides WHERE id = $1", ride_id
    )
    if started_at is None:
        raise not_found("Ride")
    if body.ended_at < started_at:
        raise unprocessable("ended_at is before the ride started")
    for i, e in enumerate(body.brake_events):
        if e.started_at < started_at - CLOCK_SKEW or e.ended_at > body.ended_at + CLOCK_SKEW:
            raise unprocessable(f"Brake event {i} is outside the ride")

    t = body.totals
    async with conn.transaction():
        await conn.execute(
            """
            UPDATE rides SET
                status = $2, ended_at = $3, analysis_window_min = $4,
                mount_realignments = $5, reported_sample_count = $6,
                max_speed_kmh = $7, max_lean_left_deg = $8,
                max_lean_right_deg = $9, max_stop_time_s = $10,
                best_decel_mps2 = $11, brake_event_count = $12,
                distance_m = $13, moving_time_s = $14,
                avg_moving_speed_kmh = $15, window_stats = $16,
                safety_stats = $17, performance = $18, updated_at = now()
            WHERE id = $1
            """,
            ride_id,
            body.status,
            body.ended_at,
            body.analysis_window_min,
            body.mount_realignments,
            body.sample_count,
            t.max_speed_kmh,
            t.max_lean_left_deg,
            t.max_lean_right_deg,
            t.max_stop_time_s,
            t.best_decel_mps2,
            t.brake_event_count,
            t.distance_m,
            t.moving_time_s,
            t.avg_moving_speed_kmh,
            body.window.model_dump(),
            body.safety_stats.model_dump() if body.safety_stats else None,
            body.performance.model_dump(exclude_none=True) if body.performance else None,
        )
        # Replace, so a retried summary leaves exactly one copy.
        await conn.execute("DELETE FROM brake_events WHERE ride_id = $1", ride_id)
        await conn.executemany(
            """
            INSERT INTO brake_events (ride_id, idx, started_at, ended_at,
                start_speed_kmh, duration_s, distance_m, peak_decel_mps2)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
            [
                (ride_id, i, e.started_at, e.ended_at, e.start_speed_kmh,
                 e.duration_s, e.distance_m, e.peak_decel_mps2)
                for i, e in enumerate(body.brake_events)
            ],
        )
    return await _load_ride(conn, ride_id)


@router.get("/{ride_id}", response_model=RideOut)
async def get_ride(ride_id: UUID, conn: Conn):
    return await _load_ride(conn, ride_id)


@router.get("/{ride_id}/analysis", response_model=WindowAnalysisOut)
async def analyse_window(
    ride_id: UUID,
    conn: Conn,
    window_min: Annotated[int, Query(ge=1, le=240)] = 15,
):
    """Recomputes the rolling-window metrics from the raw samples, the same
    way the phone does, as an independent check of the uploaded summary."""
    if not await conn.fetchval("SELECT 1 FROM rides WHERE id = $1", ride_id):
        raise not_found("Ride")
    row = await conn.fetchrow(
        """
        WITH bounds AS (
            SELECT max(recorded_at) AS window_end,
                   max(recorded_at) - make_interval(mins => $2) AS cutoff
            FROM ride_samples WHERE ride_id = $1
        ),
        win AS (
            SELECT s.* FROM ride_samples s, bounds b
            WHERE s.ride_id = $1 AND s.recorded_at >= b.cutoff
        )
        SELECT
            (SELECT count(*) FROM win)                       AS sample_count,
            (SELECT min(recorded_at) FROM win)               AS window_start,
            (SELECT window_end FROM bounds)                  AS window_end,
            (SELECT max(speed_kmh) FROM win
              WHERE speed_source IN ('gps', 'deadReckoning')) AS max_speed_kmh,
            (SELECT max(-lean_deg) FROM win
              WHERE speed_kmh >= 10 AND lean_deg < 0)        AS max_lean_left_deg,
            (SELECT max(lean_deg) FROM win
              WHERE speed_kmh >= 10 AND lean_deg > 0)        AS max_lean_right_deg,
            (SELECT max(duration_s) FROM brake_events e, bounds b
              WHERE e.ride_id = $1 AND e.started_at >= b.cutoff)  AS max_stop_time_s,
            (SELECT max(peak_decel_mps2) FROM brake_events e, bounds b
              WHERE e.ride_id = $1 AND e.started_at >= b.cutoff)  AS best_decel_mps2,
            (SELECT count(*) FROM brake_events e, bounds b
              WHERE e.ride_id = $1 AND e.started_at >= b.cutoff)  AS brake_event_count
        """,
        ride_id,
        window_min,
    )
    return {"ride_id": ride_id, "window_min": window_min, **dict(row)}


async def _load_ride(conn: asyncpg.Connection, ride_id: UUID) -> dict:
    row = await conn.fetchrow(
        f"""
        SELECT {RIDE_COLUMNS},
               (SELECT count(*) FROM ride_samples s WHERE s.ride_id = r.id)
                   AS stored_sample_count
        FROM rides r WHERE r.id = $1
        """,
        ride_id,
    )
    if row is None:
        raise not_found("Ride")
    events = await conn.fetch(
        """
        SELECT started_at, ended_at, start_speed_kmh, duration_s, distance_m,
               peak_decel_mps2
        FROM brake_events WHERE ride_id = $1 ORDER BY idx
        """,
        ride_id,
    )
    return {**dict(row), "brake_events": [dict(e) for e in events]}
