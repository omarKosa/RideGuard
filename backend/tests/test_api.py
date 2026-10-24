import uuid
from datetime import timedelta

import asyncpg
import pytest

from .conftest import T0, iso, new_id, sample, start_ride, stats


async def test_health(client):
    r = await client.get("/health")
    assert r.json() == {"status": "ok", "database": "ok"}


async def test_rider_and_bike_upserts_are_idempotent(client, bike):
    r = await client.put(
        f"/v1/bikes/{bike['bike_id']}",
        json={"rider_id": bike["rider_id"], "model": "Yamaha MT-07 ", "rated_top_speed_kmh": 210},
    )
    assert r.status_code == 200
    assert r.json()["rated_top_speed_kmh"] == 210
    assert r.json()["model"] == "Yamaha MT-07"

    # Someone else cannot take over the bike.
    other = new_id()
    await client.put(f"/v1/riders/{other}", json={})
    r = await client.put(
        f"/v1/bikes/{bike['bike_id']}",
        json={"rider_id": other, "model": "Stolen", "rated_top_speed_kmh": 100},
    )
    assert r.status_code == 409


@pytest.mark.parametrize(
    "payload, field",
    [
        ({"model": "X", "rated_top_speed_kmh": 200}, "model"),
        ({"model": "Honda CBR", "rated_top_speed_kmh": 900}, "rated_top_speed_kmh"),
        ({"model": "Honda CBR", "rated_top_speed_kmh": 200, "extra": 1}, "extra"),
    ],
)
async def test_bike_validation(client, bike, payload, field):
    r = await client.put(f"/v1/bikes/{new_id()}", json={"rider_id": bike["rider_id"], **payload})
    assert r.status_code == 422
    assert field in r.text


async def test_bike_requires_existing_rider(client):
    r = await client.put(
        f"/v1/bikes/{new_id()}",
        json={"rider_id": new_id(), "model": "Honda CBR", "rated_top_speed_kmh": 200},
    )
    assert r.status_code == 404


async def test_invalid_uuid_is_rejected(client):
    r = await client.put("/v1/riders/not-a-uuid", json={})
    assert r.status_code == 422


async def test_samples_are_deduplicated_on_retry(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    batch = {"samples": [sample(i) for i in range(50)]}

    r = await client.post(f"/v1/rides/{ride_id}/samples", json=batch)
    assert r.json() == {"received": 50, "inserted": 50, "duplicates": 0}

    # The outbox retried after a timeout: nothing is duplicated.
    r = await client.post(f"/v1/rides/{ride_id}/samples", json=batch)
    assert r.json() == {"received": 50, "inserted": 0, "duplicates": 50}

    r = await client.get(f"/v1/rides/{ride_id}")
    assert r.json()["stored_sample_count"] == 50


@pytest.mark.parametrize(
    "override, message",
    [
        ({"lean_deg": 120}, "lean_deg"),
        ({"speed_kmh": -3}, "speed_kmh"),
        ({"speed_source": "magic"}, "speed_source"),
        ({"recorded_at": "2026-01-01T00:00:00"}, "timezone"),
        ({"latitude": None}, "latitude and longitude"),
    ],
)
async def test_bad_samples_are_rejected(client, bike, override, message):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.post(
        f"/v1/rides/{ride_id}/samples", json={"samples": [sample(0, **override)]}
    )
    assert r.status_code == 422
    assert message in r.text


async def test_samples_outside_ride_time_or_duplicated_in_batch(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    early = sample(0, recorded_at=iso(T0 - timedelta(hours=2)))
    r = await client.post(f"/v1/rides/{ride_id}/samples", json={"samples": [early]})
    assert r.status_code == 422
    assert "outside the ride" in r.text

    r = await client.post(
        f"/v1/rides/{ride_id}/samples", json={"samples": [sample(1), sample(1)]}
    )
    assert r.status_code == 422
    assert "duplicate seq" in r.text

    r = await client.post(f"/v1/rides/{new_id()}/samples", json={"samples": [sample(0)]})
    assert r.status_code == 404


async def test_ride_header_retry_cannot_change_bike_or_kind(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(
        f"/v1/rides/{ride_id}",
        json={"bike_id": bike["bike_id"], "kind": "calibration",
              "started_at": iso(T0), "analysis_window_min": 15},
    )
    assert r.status_code == 409


async def test_full_calibration_then_ride_flow(client, bike):
    bike_id = bike["bike_id"]

    # 1. Init ride with its samples and summary.
    cal_ride = await start_ride(client, bike_id, kind="calibration")
    await client.post(
        f"/v1/rides/{cal_ride}/samples", json={"samples": [sample(i) for i in range(20)]}
    )
    r = await client.put(
        f"/v1/rides/{cal_ride}/summary",
        json={
            "status": "completed",
            "ended_at": iso(T0 + timedelta(minutes=5)),
            "analysis_window_min": 15,
            "mount_realignments": 0,
            "sample_count": 20,
            "totals": stats(max_speed_kmh=162),
            "window": stats(max_speed_kmh=162),
            "brake_events": [],
        },
    )
    assert r.status_code == 200, r.text

    # 2. The calibration derived from it.
    cal_id = new_id()
    calibration = {
        "bike_id": bike_id,
        "ride_id": cal_ride,
        "calibrated_at": iso(T0 + timedelta(minutes=5)),
        "mount_up": [0.0, 0.9397, 0.3420],
        "mount_forward": [0.0, -0.3420, 0.9397],
        "gyro_bias": [0.01, -0.02, 0.003],
        "linear_accel_bias": [0.0, 0.05, 0.0],
        "lean_gain": 0.97,
        "forward_from_motion": True,
        "straight_offset_deg": -8.7,
        "quality": 0.95,
        "achieved_top_speed_kmh": 162,
        "stop_time_s": 3.4,
        "stop_start_speed_kmh": 62,
        "stop_distance_m": 29.5,
        "max_decel_mps2": 7.1,
        "skipped_tasks": [],
        "warnings": [],
    }
    r = await client.put(f"/v1/calibrations/{cal_id}", json=calibration)
    assert r.status_code == 200, r.text
    assert r.json()["straight_offset_deg"] == pytest.approx(-8.7)
    # Retried upload returns the stored record.
    r = await client.put(f"/v1/calibrations/{cal_id}", json=calibration)
    assert r.status_code == 200

    # 3. A normal ride using that calibration: right-hand sweeper, then a stop.
    ride_id = await start_ride(client, bike_id, calibration_id=cal_id)
    samples = []
    for i in range(600):  # 60 s at 10 Hz
        lean = 41.5 if 200 <= i < 260 else (-33.0 if 300 <= i < 330 else 0.0)
        speed = 120.0 if i < 500 else max(0.0, 120.0 - (i - 500) * 2.5)
        samples.append(sample(i, lean_deg=lean, speed_kmh=speed))
    # A reading from a stale GPS fix must not count as top speed.
    samples[100]["speed_kmh"] = 300.0
    samples[100]["speed_source"] = "stale"
    for start in range(0, 600, 200):
        r = await client.post(
            f"/v1/rides/{ride_id}/samples", json={"samples": samples[start:start + 200]}
        )
        assert r.json()["inserted"] == 200

    brake = {
        "started_at": iso(T0 + timedelta(seconds=50)),
        "ended_at": iso(T0 + timedelta(seconds=54.8)),
        "start_speed_kmh": 120,
        "duration_s": 4.8,
        "distance_m": 80.1,
        "peak_decel_mps2": 7.4,
    }
    summary = {
        "status": "completed",
        "ended_at": iso(T0 + timedelta(seconds=60)),
        "analysis_window_min": 15,
        "mount_realignments": 1,
        "sample_count": 600,
        "totals": stats(max_speed_kmh=120, max_lean_left_deg=33, max_lean_right_deg=41.5,
                        max_stop_time_s=4.8, best_decel_mps2=7.4, brake_event_count=1,
                        distance_m=1900, moving_time_s=58, avg_moving_speed_kmh=117.9,
                        span_s=60),
        "window": stats(max_speed_kmh=120, span_s=60),
        "brake_events": [brake],
    }
    r = await client.put(f"/v1/rides/{ride_id}/summary", json=summary)
    assert r.status_code == 200, r.text
    # Retrying the summary keeps exactly one brake event.
    r = await client.put(f"/v1/rides/{ride_id}/summary", json=summary)
    body = r.json()
    assert body["status"] == "completed"
    assert body["calibration_id"] == cal_id
    assert body["stored_sample_count"] == body["reported_sample_count"] == 600
    assert len(body["brake_events"]) == 1
    assert body["window_stats"]["max_speed_kmh"] == 120

    # 4. The server recomputes the window from raw samples and agrees.
    r = await client.get(f"/v1/rides/{ride_id}/analysis", params={"window_min": 15})
    a = r.json()
    assert a["sample_count"] == 600
    assert a["max_speed_kmh"] == pytest.approx(120)  # stale 300 ignored
    assert a["max_lean_right_deg"] == pytest.approx(41.5)
    assert a["max_lean_left_deg"] == pytest.approx(33)
    assert a["max_stop_time_s"] == pytest.approx(4.8)
    assert a["brake_event_count"] == 1

    # The window is anchored at the last sample: 1 minute covers this whole
    # 60 s ride, while a longer ride would only show its tail.
    a = (await client.get(f"/v1/rides/{ride_id}/analysis", params={"window_min": 1})).json()
    assert a["sample_count"] == 600
    assert a["window_end"] is not None

    # 5. Bike-level history.
    r = await client.get(f"/v1/bikes/{bike_id}/stats")
    st = r.json()
    assert st["ride_count"] == 1  # calibration rides are not counted
    assert st["max_lean_right_deg"] == pytest.approx(41.5)
    assert st["latest_calibration"]["id"] == cal_id
    rides = (await client.get(f"/v1/bikes/{bike_id}/rides")).json()
    assert {r["kind"] for r in rides} == {"ride", "calibration"}


async def test_calibration_validation(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])  # a normal ride
    base = {
        "bike_id": bike["bike_id"],
        "ride_id": ride_id,
        "calibrated_at": iso(T0),
        "mount_up": [0, 0, 1],
        "mount_forward": [1, 0, 0],
        "gyro_bias": [0, 0, 0],
        "linear_accel_bias": [0, 0, 0],
        "lean_gain": 1,
        "forward_from_motion": True,
        "straight_offset_deg": 0,
        "quality": 1,
    }
    r = await client.put(f"/v1/calibrations/{new_id()}", json=base)
    assert r.status_code == 422
    assert "not a calibration ride" in r.text

    cal_ride = await start_ride(client, bike["bike_id"], kind="calibration")
    r = await client.put(
        f"/v1/calibrations/{new_id()}",
        json={**base, "ride_id": cal_ride, "mount_forward": [0, 0.3, 1]},
    )
    assert r.status_code == 422
    assert "unit vector" in r.text or "perpendicular" in r.text

    r = await client.put(
        f"/v1/calibrations/{new_id()}", json={**base, "ride_id": cal_ride, "mount_up": [0, 1]}
    )
    assert r.status_code == 422


async def test_database_constraints_back_up_the_api(client, bike):
    """Even if validation were bypassed, Postgres refuses impossible data."""
    ride_id = await start_ride(client, bike["bike_id"])
    async with client.app.state.pool.acquire() as conn:
        with pytest.raises(asyncpg.CheckViolationError):
            await conn.execute(
                """INSERT INTO ride_samples (ride_id, seq, recorded_at, speed_kmh,
                   speed_source, lean_deg, roll_rate_dps, yaw_rate_dps,
                   forward_accel_mps2, lateral_accel_mps2)
                   VALUES ($1, 0, now(), 50, 'gps', 95, 0, 0, 0, 0)""",
                uuid.UUID(ride_id),
            )


async def _put_bike(client, rider_id, **extra):
    return await client.put(
        f"/v1/bikes/{new_id()}",
        json={"rider_id": rider_id, "model": "Suzuki GSX-S1000",
              "rated_top_speed_kmh": 240, **extra},
    )


async def test_bike_with_catalogue_model(client, bike):
    extra = {"catalogue_model_id": "suzuki-gsx-s1000-2021",
             "catalogue_version": "2026-10-24", "top_speed_source": "catalogue"}
    r = await _put_bike(client, bike["rider_id"], **extra)
    assert r.status_code == 200, r.text
    for k, v in extra.items():
        assert r.json()[k] == v
    assert r.json()["other_make"] is None


async def test_bike_with_unknown_catalogue_id_is_accepted(client, bike):
    r = await _put_bike(client, bike["rider_id"], catalogue_model_id="brand-new-2027")
    assert r.status_code == 200, r.text
    assert r.json()["top_speed_source"] == "rider"


async def test_bike_other_fields_and_exclusivity(client, bike):
    r = await _put_bike(client, bike["rider_id"], other_make="Foo",
                        other_model="Bar 200", other_year=2019)
    assert r.status_code == 200, r.text
    assert r.json()["other_make"] == "Foo" and r.json()["other_year"] == 2019
    r = await _put_bike(client, bike["rider_id"],
                        catalogue_model_id="suzuki-gsx-s1000-2021", other_model="Bar")
    assert r.status_code == 422


async def test_rider_phone_fields(client):
    rid = new_id()
    r = await client.put(f"/v1/riders/{rid}", json={
        "platform": "android", "phone_model": "SM-S918B", "os_version": "Android 15"})
    assert r.status_code == 200, r.text
    assert r.json()["phone_model"] == "SM-S918B"
    assert r.json()["os_version"] == "Android 15"
    assert (await client.get(f"/v1/riders/{rid}")).json()["os_version"] == "Android 15"
