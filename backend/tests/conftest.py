"""Tests run against a real Postgres (the compose `db` service) in a
dedicated `<name>_test` database that is recreated for each session."""

import os
import uuid
from datetime import datetime, timedelta, timezone

import asyncpg
import httpx
import pytest

from app.main import create_app

BASE_DSN = os.environ["DATABASE_URL"]
TEST_DB = BASE_DSN.rsplit("/", 1)[1].split("?")[0] + "_test"
TEST_DSN = BASE_DSN.rsplit("/", 1)[0] + "/" + TEST_DB

_db_ready = False


async def _recreate_test_db() -> None:
    admin = await asyncpg.connect(BASE_DSN)
    try:
        await admin.execute(f'DROP DATABASE IF EXISTS "{TEST_DB}" WITH (FORCE)')
        await admin.execute(f'CREATE DATABASE "{TEST_DB}"')
    finally:
        await admin.close()


@pytest.fixture
async def client():
    global _db_ready
    if not _db_ready:
        await _recreate_test_db()
        _db_ready = True
    app = create_app(TEST_DSN)
    async with app.router.lifespan_context(app):
        async with app.state.pool.acquire() as conn:
            await conn.execute(
                "TRUNCATE riders, bikes, rides, calibrations, ride_samples, "
                "brake_events, incidents, model_checks CASCADE"
            )
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
            c.app = app
            yield c


def new_id() -> str:
    return str(uuid.uuid4())


T0 = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(hours=1)


def iso(dt: datetime) -> str:
    return dt.isoformat()


def sample(seq: int, **overrides) -> dict:
    s = {
        "seq": seq,
        "recorded_at": iso(T0 + timedelta(milliseconds=100 * seq)),
        "speed_kmh": 50.0,
        "speed_source": "gps",
        "lean_deg": 0.0,
        "roll_rate_dps": 0.0,
        "yaw_rate_dps": 0.0,
        "forward_accel_mps2": 0.0,
        "lateral_accel_mps2": 0.0,
        "latitude": 30.05,
        "longitude": 31.24,
        "gps_accuracy_m": 4.0,
    }
    s.update(overrides)
    return s


def stats(**overrides) -> dict:
    s = {
        "max_speed_kmh": 0,
        "max_lean_left_deg": 0,
        "max_lean_right_deg": 0,
        "max_stop_time_s": 0,
        "best_decel_mps2": 0,
        "brake_event_count": 0,
        "distance_m": 0,
        "moving_time_s": 0,
        "avg_moving_speed_kmh": 0,
        "span_s": 0,
    }
    s.update(overrides)
    return s


@pytest.fixture
async def bike(client):
    rider_id, bike_id = new_id(), new_id()
    r = await client.put(f"/v1/riders/{rider_id}", json={"platform": "android"})
    assert r.status_code == 200, r.text
    r = await client.put(
        f"/v1/bikes/{bike_id}",
        json={"rider_id": rider_id, "model": "Yamaha MT-07", "rated_top_speed_kmh": 214},
    )
    assert r.status_code == 200, r.text
    return {"rider_id": rider_id, "bike_id": bike_id}


async def start_ride(client, bike_id: str, kind: str = "ride", **extra) -> str:
    ride_id = new_id()
    r = await client.put(
        f"/v1/rides/{ride_id}",
        json={
            "bike_id": bike_id,
            "kind": kind,
            "started_at": iso(T0),
            "analysis_window_min": 15,
            **extra,
        },
    )
    assert r.status_code == 200, r.text
    return ride_id


async def make_calibration(client, bike_id: str) -> tuple[str, str]:
    """Stores a calibration (and its init ride) for the bike. Returns
    (calibration_id, ride_id)."""
    ride_id = await start_ride(client, bike_id, kind="calibration")
    cal_id = new_id()
    r = await client.put(
        f"/v1/calibrations/{cal_id}",
        json={
            "bike_id": bike_id,
            "ride_id": ride_id,
            "calibrated_at": iso(T0 + timedelta(minutes=5)),
            "mount_up": [0.0, 0.9397, 0.3420],
            "mount_forward": [0.0, -0.3420, 0.9397],
            "gyro_bias": [0.0, 0.0, 0.0],
            "linear_accel_bias": [0.0, 0.0, 0.0],
            "lean_gain": 1.0,
            "forward_from_motion": True,
            "straight_offset_deg": 0.0,
            "quality": 0.9,
            "skipped_tasks": [],
            "warnings": [],
        },
    )
    assert r.status_code == 200, r.text
    return cal_id, ride_id
