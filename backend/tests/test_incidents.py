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


def label(value: str) -> dict:
    return {"rider_label": value, "labelled_at": iso(T0 + timedelta(minutes=13))}


def wobble_body() -> dict:
    return crash(kind="wobble", outcome="warned", wobble_hz=7.2, wobble_rms=0.64,
                 peak_accel_g=None)


async def test_rider_label_yes_and_no(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    url = f"/v1/rides/{ride_id}/incidents/{new_id()}"
    r = await client.put(url, json=wobble_body())
    assert r.status_code == 200, r.text
    assert r.json()["false_alarm"] is False
    assert r.json()["rider_label"] is None
    assert r.json()["labelled_at"] is None
    assert r.json()["wobble_rms"] == pytest.approx(0.64)

    r = await client.put(url, json=wobble_body() | label("no"))
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] == "no"
    assert r.json()["labelled_at"] is not None
    assert r.json()["false_alarm"] is True

    r = await client.put(url, json=wobble_body() | label("yes"))
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] == "yes"
    assert r.json()["false_alarm"] is False


async def test_crash_can_be_labelled_no_without_false_alarm(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=crash(**resolved("cancelled")) | label("no"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] == "no"
    assert r.json()["false_alarm"] is False

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


async def test_label_requires_labelled_at(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    url = f"/v1/rides/{ride_id}/incidents/{new_id()}"
    r = await client.put(url, json=wobble_body() | {"rider_label": "no"})
    assert r.status_code == 422
    r = await client.put(
        url, json=wobble_body() | {"labelled_at": iso(T0 + timedelta(minutes=13))}
    )
    assert r.status_code == 422
    r = await client.put(url, json=wobble_body() | label("maybe"))
    assert r.status_code == 422
    r = await client.put(
        url,
        json=wobble_body() | {"rider_label": "no", "labelled_at": iso(T0)},
    )
    assert r.status_code == 422
    assert "labelled_at" in r.text


async def test_legacy_false_alarm_is_still_accepted(client, bike):
    # Jobs queued by the previous app version still carry false_alarm.
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=wobble_body() | {"false_alarm": True},
    )
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] == "no"
    assert r.json()["labelled_at"] == r.json()["detected_at"]
    assert r.json()["false_alarm"] is True

    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=wobble_body() | {"false_alarm": False},
    )
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] is None

    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=crash(**resolved("cancelled")) | {"false_alarm": False},
    )
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] is None
    assert r.json()["false_alarm"] is False

    # A crash never becomes a label this way.
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=crash(**resolved("cancelled")) | {"false_alarm": True},
    )
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] is None
    assert r.json()["false_alarm"] is False

    # An explicit label wins over the legacy flag.
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{new_id()}",
        json=wobble_body() | label("yes") | {"false_alarm": True},
    )
    assert r.status_code == 200, r.text
    assert r.json()["rider_label"] == "yes"
    assert r.json()["false_alarm"] is False


def clip(**overrides) -> dict:
    body = {
        "rate_hz": 50.0,
        "start_offset_s": -5.0,
        "accel": [[-5.0 + 0.02 * i, 0.1, 9.8, 0.2] for i in range(10)],
        "gyro": [[-5.0 + 0.02 * i, 0.0, 0.1, 0.0] for i in range(10)],
    }
    body.update(overrides)
    return body


async def test_clip_upload_and_replace(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    incident_id = new_id()
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{incident_id}", json=wobble_body()
    )
    assert r.status_code == 200, r.text
    url = f"/v1/rides/{ride_id}/incidents/{incident_id}/clip"

    r = await client.put(url, json=clip())
    assert r.status_code == 204, r.text
    r = await client.put(url, json=clip(rate_hz=100.0, accel=[[0, 1, 2, 3]]))
    assert r.status_code == 204, r.text

    async with client.app.state.pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM incident_clips")
    [row] = rows
    assert row["rate_hz"] == 100.0
    assert row["accel"] == [[0, 1, 2, 3]]

    # Wrong ride or unknown incident: 404.
    other = await start_ride(client, bike["bike_id"])
    r = await client.put(f"/v1/rides/{other}/incidents/{incident_id}/clip", json=clip())
    assert r.status_code == 404
    r = await client.put(f"/v1/rides/{ride_id}/incidents/{new_id()}/clip", json=clip())
    assert r.status_code == 404


@pytest.mark.parametrize(
    "override",
    [
        {"accel": [[0.0, 1.0, 2.0]]},
        {"gyro": [[0.0, 1.0, 2.0, 3.0, 4.0]]},
        {"accel": [[0.0, 1.0, 2.0, 3.0]] * 1501},
        {"rate_hz": 0},
        {"rate_hz": 2000},
        {"start_offset_s": 1.0},
        {"start_offset_s": -11.0},
        {"extra": 1},
    ],
)
async def test_clip_rejects_bad_rows(client, bike, override):
    ride_id = await start_ride(client, bike["bike_id"])
    incident_id = new_id()
    await client.put(f"/v1/rides/{ride_id}/incidents/{incident_id}", json=wobble_body())
    r = await client.put(
        f"/v1/rides/{ride_id}/incidents/{incident_id}/clip", json=clip(**override)
    )
    assert r.status_code == 422


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


BAND = {
    "band": "40-60",
    "seconds": 300,
    "wobble_rms": {"min": 0.01, "max": 2.0, "counts": [1] * 40},
    "wobble_hz": {"min": 0.5, "max": 12.0, "counts": [0] * 40},
    "peak_g": {"min": 0.5, "max": 8.0, "counts": [2] * 40},
}
PERFORMANCE = {
    "sustained_top_speed_kmh": 131.0,
    "peak_accel_mps2": 5.2,
    "peak_decel_mps2": None,
    "stops": [{"start_speed_kmh": 80.0, "duration_s": 6.5, "mean_decel_mps2": 3.4}],
}


async def test_summary_with_bands_and_performance(client, bike):
    ride_id = await start_ride(client, bike["bike_id"])
    r = await client.put(
        f"/v1/rides/{ride_id}/summary",
        json=summary(
            safety_stats=SAFETY_STATS | {"bands": [BAND]}, performance=PERFORMANCE
        ),
    )
    assert r.status_code == 200, r.text
    r = await client.get(f"/v1/rides/{ride_id}")
    body = r.json()
    assert body["safety_stats"]["bands"][0]["band"] == "40-60"
    assert body["safety_stats"]["bands"][0]["peak_g"]["counts"] == [2] * 40
    assert body["performance"]["sustained_top_speed_kmh"] == 131.0
    assert body["performance"]["stops"][0]["duration_s"] == 6.5

    # Empty bands and absent/null performance are fine.
    for extra in ({"safety_stats": SAFETY_STATS | {"bands": []}},
                  {"safety_stats": SAFETY_STATS, "performance": None}):
        other = await start_ride(client, bike["bike_id"])
        r = await client.put(f"/v1/rides/{other}/summary", json=summary(**extra))
        assert r.status_code == 200, r.text
        assert r.json()["performance"] is None

    bad = BAND | {"band": "10-20"}
    r = await client.put(
        f"/v1/rides/{ride_id}/summary",
        json=summary(safety_stats=SAFETY_STATS | {"bands": [bad]}),
    )
    assert r.status_code == 422
    bad = BAND | {"peak_g": {"min": 5, "max": 2, "counts": []}}
    r = await client.put(
        f"/v1/rides/{ride_id}/summary",
        json=summary(safety_stats=SAFETY_STATS | {"bands": [bad]}),
    )
    assert r.status_code == 422
