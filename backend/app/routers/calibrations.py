from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends

from ..deps import get_conn, not_found, unprocessable
from ..schemas import CalibrationIn, CalibrationOut

router = APIRouter(prefix="/v1/calibrations", tags=["calibrations"])
Conn = Annotated[asyncpg.Connection, Depends(get_conn)]


@router.put("/{calibration_id}", response_model=CalibrationOut)
async def upsert_calibration(calibration_id: UUID, body: CalibrationIn, conn: Conn):
    ride = await conn.fetchrow(
        "SELECT bike_id, kind FROM rides WHERE id = $1", body.ride_id
    )
    if ride is None:
        raise not_found("Calibration ride")
    if ride["bike_id"] != body.bike_id:
        raise unprocessable("Calibration ride belongs to a different bike")
    if ride["kind"] != "calibration":
        raise unprocessable("Referenced ride is not a calibration ride")

    row = await conn.fetchrow(
        """
        INSERT INTO calibrations (
            id, bike_id, ride_id, calibrated_at, mount_up, mount_forward,
            gyro_bias, linear_accel_bias, lean_gain, forward_from_motion,
            straight_offset_deg, quality, achieved_top_speed_kmh, stop_time_s,
            stop_start_speed_kmh, stop_distance_m, max_decel_mps2,
            skipped_tasks, warnings)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                $15, $16, $17, $18, $19)
        ON CONFLICT (id) DO NOTHING
        RETURNING *
        """,
        calibration_id,
        body.bike_id,
        body.ride_id,
        body.calibrated_at,
        body.mount_up,
        body.mount_forward,
        body.gyro_bias,
        body.linear_accel_bias,
        body.lean_gain,
        body.forward_from_motion,
        body.straight_offset_deg,
        body.quality,
        body.achieved_top_speed_kmh,
        body.stop_time_s,
        body.stop_start_speed_kmh,
        body.stop_distance_m,
        body.max_decel_mps2,
        body.skipped_tasks,
        body.warnings,
    )
    # Calibrations are immutable; a retry returns the stored record.
    if row is None:
        row = await conn.fetchrow(
            "SELECT * FROM calibrations WHERE id = $1", calibration_id
        )
    return dict(row)


@router.get("/{calibration_id}", response_model=CalibrationOut)
async def get_calibration(calibration_id: UUID, conn: Conn):
    row = await conn.fetchrow(
        "SELECT * FROM calibrations WHERE id = $1", calibration_id
    )
    if row is None:
        raise not_found("Calibration")
    return dict(row)
