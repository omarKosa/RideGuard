from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends

from ..deps import conflict, get_conn, not_found, unprocessable
from ..schemas import ModelCheckIn, ModelCheckOut

router = APIRouter(prefix="/v1/bikes", tags=["model checks"])
Conn = Annotated[asyncpg.Connection, Depends(get_conn)]

CHECK_COLUMNS = """
    id, bike_id, calibration_id, ride_id, reason, catalogue_model_id,
    catalogue_version, other_make, other_model, other_year, phone_model,
    imu_hz, expected, measured, results, mismatch, checked_at, created_at
"""


@router.put("/{bike_id}/model-checks/{check_id}", response_model=ModelCheckOut)
async def put_model_check(bike_id: UUID, check_id: UUID, body: ModelCheckIn, conn: Conn):
    if not await conn.fetchval("SELECT 1 FROM bikes WHERE id = $1", bike_id):
        raise not_found("Bike")
    if not await conn.fetchval(
        "SELECT 1 FROM calibrations WHERE id = $1 AND bike_id = $2",
        body.calibration_id,
        bike_id,
    ):
        raise unprocessable("Calibration does not belong to this bike")
    if not await conn.fetchval(
        "SELECT 1 FROM rides WHERE id = $1 AND bike_id = $2", body.ride_id, bike_id
    ):
        raise unprocessable("Ride does not belong to this bike")

    row = await conn.fetchrow(
        f"""
        INSERT INTO model_checks (id, bike_id, calibration_id, ride_id, reason,
            catalogue_model_id, catalogue_version, other_make, other_model,
            other_year, phone_model, imu_hz, expected, measured, results,
            mismatch, checked_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                $15, $16, $17)
        ON CONFLICT (id) DO NOTHING
        RETURNING {CHECK_COLUMNS}
        """,
        check_id,
        bike_id,
        body.calibration_id,
        body.ride_id,
        body.reason,
        body.catalogue_model_id,
        body.catalogue_version,
        body.other_make,
        body.other_model,
        body.other_year,
        body.phone_model,
        body.imu_hz,
        body.expected.model_dump(exclude_none=True) if body.expected else None,
        body.measured.model_dump(exclude_none=True),
        body.results.model_dump(),
        body.mismatch,
        body.checked_at,
    )
    if row is None:  # retry: the first write wins
        row = await conn.fetchrow(
            f"SELECT {CHECK_COLUMNS} FROM model_checks WHERE id = $1", check_id
        )
        if row["bike_id"] != bike_id:
            raise conflict("Model check belongs to another bike")
    return dict(row)


@router.get("/{bike_id}/model-checks", response_model=list[ModelCheckOut])
async def list_model_checks(bike_id: UUID, conn: Conn):
    rows = await conn.fetch(
        f"""
        SELECT {CHECK_COLUMNS} FROM model_checks WHERE bike_id = $1
        ORDER BY checked_at DESC, created_at DESC
        """,
        bike_id,
    )
    return [dict(r) for r in rows]
