from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response

from ..deps import conflict, get_conn, not_found, unprocessable
from ..schemas import ClipIn, IncidentIn, IncidentOut
from .rides import CLOCK_SKEW

router = APIRouter(prefix="/v1/rides", tags=["incidents"])
Conn = Annotated[asyncpg.Connection, Depends(get_conn)]

INCIDENT_COLUMNS = """
    id, ride_id, kind, detected_at, speed_kmh, lean_deg, peak_accel_g,
    wobble_hz, wobble_rms, latitude, longitude, outcome, resolved_at,
    rider_label, labelled_at, false_alarm
"""


@router.put("/{ride_id}/incidents/{incident_id}", response_model=IncidentOut)
async def upsert_incident(ride_id: UUID, incident_id: UUID, body: IncidentIn, conn: Conn):
    started_at = await conn.fetchval(
        "SELECT started_at FROM rides WHERE id = $1", ride_id
    )
    if started_at is None:
        raise not_found("Ride")
    latest_allowed = datetime.now(timezone.utc) + CLOCK_SKEW
    if body.detected_at < started_at - CLOCK_SKEW or body.detected_at > latest_allowed:
        raise unprocessable("detected_at is outside the ride's time range")
    if body.resolved_at is not None and body.resolved_at > latest_allowed:
        raise unprocessable("resolved_at is in the future")

    row = await conn.fetchrow(
        f"""
        INSERT INTO incidents (id, ride_id, kind, detected_at, speed_kmh,
            lean_deg, peak_accel_g, wobble_hz, wobble_rms, latitude,
            longitude, outcome, resolved_at, rider_label, labelled_at, false_alarm)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                $15, $16)
        ON CONFLICT (id) DO UPDATE
            SET outcome = EXCLUDED.outcome,
                resolved_at = EXCLUDED.resolved_at,
                rider_label = EXCLUDED.rider_label,
                labelled_at = EXCLUDED.labelled_at,
                false_alarm = EXCLUDED.false_alarm,
                updated_at = now()
            -- Only the outcome (away from 'pending') and the rider's
            -- label change; a retried request is a no-op.
            WHERE incidents.ride_id = EXCLUDED.ride_id
              AND incidents.kind = EXCLUDED.kind
              AND (incidents.outcome = 'pending'
                   OR incidents.outcome = EXCLUDED.outcome)
        RETURNING {INCIDENT_COLUMNS}
        """,
        incident_id,
        ride_id,
        body.kind,
        body.detected_at,
        body.speed_kmh,
        body.lean_deg,
        body.peak_accel_g,
        body.wobble_hz,
        body.wobble_rms,
        body.latitude,
        body.longitude,
        body.outcome,
        body.resolved_at,
        body.rider_label,
        body.labelled_at,
        body.rider_label == "no" and body.kind != "crash",
    )
    if row is None:
        raise conflict("Incident already exists with a different ride, kind or outcome")
    return dict(row)


@router.get("/{ride_id}/incidents", response_model=list[IncidentOut])
async def list_incidents(ride_id: UUID, conn: Conn):
    if not await conn.fetchval("SELECT 1 FROM rides WHERE id = $1", ride_id):
        raise not_found("Ride")
    rows = await conn.fetch(
        f"""
        SELECT {INCIDENT_COLUMNS} FROM incidents
        WHERE ride_id = $1 ORDER BY detected_at, id
        """,
        ride_id,
    )
    return [dict(r) for r in rows]


@router.put("/{ride_id}/incidents/{incident_id}/clip", status_code=204)
async def put_clip(ride_id: UUID, incident_id: UUID, body: ClipIn, conn: Conn):
    if not await conn.fetchval(
        "SELECT 1 FROM incidents WHERE id = $1 AND ride_id = $2", incident_id, ride_id
    ):
        raise not_found("Incident")
    await conn.execute(
        """
        INSERT INTO incident_clips (incident_id, rate_hz, start_offset_s, accel, gyro)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (incident_id) DO UPDATE
            SET rate_hz = EXCLUDED.rate_hz,
                start_offset_s = EXCLUDED.start_offset_s,
                accel = EXCLUDED.accel,
                gyro = EXCLUDED.gyro,
                created_at = now()
        """,
        incident_id, body.rate_hz, body.start_offset_s, body.accel, body.gyro,
    )
    return Response(status_code=204)
