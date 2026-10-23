from datetime import timedelta

import asyncpg
import pytest

from .conftest import T0, iso, new_id, start_ride, stats


def crash(**overrides) -> dict:
    body = {
        "kind": "crash",
        "detected_at": iso(T0 + timedelta(minutes=12)),
        "speed_kmh": 62.5,
        "lean_deg": 38.0,
        "peak_accel_g": 7.4,
        "latitude": 30.05,
        "longitude": 31.24,
        "outcome": "pending",
    }
    body.update(overrides)
    return body


def resolved(outcome: str) -> dict:
    return {"outcome": outcome, "resolved_at": iso(T0 + timedelta(minutes=12, seconds=30))}


async def test_crash_lifecycle_and_retries(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    incident_id = new_id()
    url = f"/v1/rides/{ride_id}/incidents/{incident_id}"

    r = await client.put(url, json=crash())
    assert r.status_code == 200, r.text
    assert r.json()["outcome"] == "pending"

    r = await client.put(url, json=crash(**resolved("called")))
    assert r.status_code == 200, r.text
    assert r.json()["outcome"] == "called"

    # The outbox retried the final update: same result, no duplicate.
    r = await client.put(url, json=crash(**resolved("called")))
    assert r.status_code == 200

    # A resolved crash cannot be reopened or re-resolved differently.
    r = await client.put(url, json=crash())
    assert r.status_code == 409
    r = await client.put(url, json=crash(**resolved("cancelled")))
    assert r.status_code == 409

    r = await client.get(f"/v1/rides/{ride_id}/incidents")
    assert r.status_code == 200
    [stored] = r.json()
    assert stored["id"] == incident_id
    assert stored["kind"] == "crash"
    assert stored["outcome"] == "called"
    assert stored["peak_accel_g"] == pytest.approx(7.4)
    assert stored["latitude"] == 30.05


async def test_warnings_are_listed_in_order(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    wobble = crash(kind="wobble", outcome="warned", wobble_hz=6.8, peak_accel_g=None,
                   detected_at=iso(T0 + timedelta(minutes=5)))
    impact = crash(kind="impact", outcome="warned", latitude=None, longitude=None)
    for body in (impact, wobble):
        r = await client.put(f"/v1/rides/{ride_id}/incidents/{new_id()}", json=body)
        assert r.status_code == 200, r.text

    r = await client.get(f"/v1/rides/{ride_id}/incidents")
    assert [i["kind"] for i in r.json()] == ["wobble", "impact"]
    assert r.json()[0]["wobble_hz"] == pytest.approx(6.8)


@pytest.mark.parametrize(
    "override, message",
    [
        ({"kind": "explosion"}, "kind"),
        ({"outcome": "warned"}, "crashes are pending or resolved"),
        ({"kind": "wobble"}, "other incidents are 'warned'"),
        ({"outcome": "called"}, "resolved_at does not match"),
        (resolved("cancelled") | {"outcome": "pending"}, "resolved_at does not match"),
        ({"latitude": None}, "latitude and longitude"),
        ({"speed_kmh": -1}, "speed_kmh"),
        ({"wobble_hz": 0}, "wobble_hz"),
        ({"detected_at": iso(T0 - timedelta(hours=2))}, "outside the ride"),
        ({"resolved_at": iso(T0), "outcome": "called"}, "before detected_at"),
    ],
)
async def test_bad_incidents_are_rejected(client, bike, override, message):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}", json=crash(**override)
    )
    assert r.status_code == 422
    assert message in r.text


async def test_incident_needs_an_existing_ride(client, bike):
    r = await client.put(f"/v1/rides/{new_id()}/incidents/{new_id()}", json=crash())
    assert r.status_code == 404
    r = await client.get(f"/v1/rides/{new_id()}/incidents")
    assert r.status_code == 404


async def test_incident_cannot_move_to_another_ride(client, bike):
    ride_a = await start_ride(client, bike["bike_id"])
    ride_b = await start_ride(client, bike["bike_id"])
    incident_id = new_id()
    r = await client.put(f"/v1/rides/{ride_a}/incidents/{incident_id}", json=crash())
    assert r.status_code == 200
    r = await client.put(f"/v1/rides/{ride_b}/incidents/{incident_id}", json=crash())
    assert r.status_code == 409


async def test_database_enforces_incident_rules(client, bike):
    """Pydantic should catch these first; the constraints are the backstop."""
    ride_id = await start_ride(client, bike["bike_id"])
    async with client.app.state.pool.acquire() as conn:
        with pytest.raises(asyncpg.CheckViolationError):
            await conn.execute(
                """
                INSERT INTO incidents (id, ride_id, kind, detected_at, speed_kmh,
                                       lean_deg, outcome)
                VALUES ($1, $2, 'wobble', $3, 50, 0, 'called')
                """,
                new_id(), ride_id, T0,
            )


# ------------------------------------------------------------ safety learning


async def test_rider_can_mark_a_warning_as_false_alarm(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    url = f"/v1/rides/{ride_id}/incidents/{new_id()}"
    wobble = crash(kind="wobble", outcome="warned", wobble_hz=7.2, wobble_rms=0.64,
                   peak_accel_g=None)
    r = await client.put(url, json=wobble)
    assert r.status_code == 200, r.text
    assert r.json()["false_alarm"] is False
    assert r.json()["wobble_rms"] == pytest.approx(0.64)

    r = await client.put(url, json=wobble | {"false_alarm": True})
    assert r.status_code == 200, r.text
    assert r.json()["false_alarm"] is True


async def test_a_crash_is_never_a_false_alarm(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=crash(false_alarm=True, **resolved("cancelled")),
    )
    assert r.status_code == 422
    assert "cannot be marked as a false alarm" in r.text

    async with client.app.state.pool.acquire() as conn:
        with pytest.raises(asyncpg.CheckViolationError):
            await conn.execute(
                """
                INSERT INTO incidents (id, ride_id, kind, detected_at, speed_kmh,
                                       lean_deg, outcome, false_alarm)
                VALUES ($1, $2, 'crash', $3, 50, 0, 'pending', true)
                """,
                new_id(), ride_id, T0,
            )


SAFETY_STATS = {
    "riding_s": 1840,
    "wobble_rms_p99": 0.21,
    "peak_g_p99": 2.4,
    "imu_hz": 50,
    "wobble_threshold_rms": 0.63,
    "wobble_max_hz": 12,
    "impact_threshold_g": 4.0,
    "extreme_lean_deg": 55,
}


def summary(**extra) -> dict:
    return {
        "status": "completed",
        "ended_at": iso(T0 + timedelta(minutes=40)),
        "analysis_window_min": 15,
        "mount_realignments": 0,
        "sample_count": 0,
        "totals": stats(),
        "window": stats(),
        "brake_events": [],
        **extra,
    }


async def test_ride_summary_keeps_safety_stats(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(f"/v1/rides/{ride_id}/summary", json=summary(safety_stats=SAFETY_STATS))
    assert r.status_code == 200, r.text
    assert r.json()["safety_stats"]["wobble_threshold_rms"] == 0.63

    # Older app versions send no safety stats.
    other = await start_ride(client, bike["bike_id"])
    r = await client.put(f"/v1/rides/{other}/summary", json=summary())
    assert r.status_code == 200, r.text
    assert r.json()["safety_stats"] is None

    bad = SAFETY_STATS | {"impact_threshold_g": 0}
    r = await client.put(f"/v1/rides/{ride_id}/summary", json=summary(safety_stats=bad))
    assert r.status_code == 422
    assert "impact_threshold_g" in r.text
