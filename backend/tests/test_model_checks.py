import pytest

from app.reports import fetch_report

from .conftest import T0, iso, make_calibration, new_id, start_ride  # noqa: F401

MEASURED = {
    "sustained_top_speed_kmh": 171.0,
    "peak_accel_mps2": 6.1,
    "peak_decel_mps2": 8.2,
    "stops": [{"start_speed_kmh": 90, "duration_s": 3.1, "mean_decel_mps2": 8.0}],
}
OK = {"top_speed": "match", "acceleration": "not_tested", "braking": "match"}


async def body_for(client, bike_id, **over):
    cal_id, ride_id = await make_calibration(client, bike_id)
    body = {
        "reason": "init_ride",
        "calibration_id": cal_id,
        "ride_id": ride_id,
        "checked_at": iso(T0),
        "catalogue_model_id": "suzuki-gsx-s1000-2021",
        "catalogue_version": "1",
        "phone_model": "Pixel 8",
        "imu_hz": 100.0,
        "expected": {"top_speed_kmh": 250, "max_accel_mps2": 12, "max_decel_mps2": 11},
        "measured": MEASURED,
        "results": OK,
        "mismatch": False,
    }
    body.update(over)
    return body


async def test_model_check_roundtrip_and_retry(client, bike):
    bike_id = bike["bike_id"]
    body = await body_for(client, bike_id)
    cid = new_id()
    for _ in range(2):
        r = await client.put(f"/v1/bikes/{bike_id}/model-checks/{cid}", json=body)
        assert r.status_code == 200, r.text
    assert r.json()["measured"]["stops"][0]["duration_s"] == 3.1
    assert r.json()["phone_model"] == "Pixel 8"
    rows = (await client.get(f"/v1/bikes/{bike_id}/model-checks")).json()
    assert [x["id"] for x in rows] == [cid]


async def test_model_check_mismatch_flag_must_match_results(client, bike):
    bike_id = bike["bike_id"]
    body = await body_for(
        client, bike_id, results={**OK, "top_speed": "mismatch"}, mismatch=False
    )
    r = await client.put(f"/v1/bikes/{bike_id}/model-checks/{new_id()}", json=body)
    assert r.status_code == 422


async def test_model_check_other_bike_shows_in_gaps(client, bike):
    bike_id = bike["bike_id"]
    r = await client.put(
        f"/v1/bikes/{bike_id}",
        json={"rider_id": bike["rider_id"], "model": "CFMoto 450NK",
              "rated_top_speed_kmh": 170, "other_make": "CFMoto",
              "other_model": "450NK", "other_year": 2024},
    )
    assert r.status_code == 200, r.text
    body = await body_for(
        client, bike_id, catalogue_model_id=None, catalogue_version=None,
        other_make="CFMoto", other_model="450NK", other_year=2024, expected=None,
    )
    r = await client.put(f"/v1/bikes/{bike_id}/model-checks/{new_id()}", json=body)
    assert r.status_code == 200, r.text
    async with client.app.state.pool.acquire() as conn:
        rows = await fetch_report(conn, "gaps")
    row = next(x for x in rows if x["model"] == "450nk")
    assert row["make"] == "cfmoto"
    assert row["max_sustained_speed_kmh"] == pytest.approx(171.0)
    assert row["bikes"] == 1


async def test_mismatch_report(client, bike):
    bike_id = bike["bike_id"]
    bad = await body_for(
        client, bike_id, results={**OK, "top_speed": "mismatch"}, mismatch=True
    )
    good = await body_for(client, bike_id)
    for b in (bad, good):
        r = await client.put(f"/v1/bikes/{bike_id}/model-checks/{new_id()}", json=b)
        assert r.status_code == 200, r.text
    async with client.app.state.pool.acquire() as conn:
        rows = await fetch_report(conn, "mismatches")
    row = next(x for x in rows if x["catalogue_model_id"] == "suzuki-gsx-s1000-2021")
    assert row["checks"] == 2 and row["mismatches"] == 1
    assert "top_speed" in row["mismatch_items"]


async def test_model_check_wrong_bike_calibration(client, bike):
    other_rider, other_bike = new_id(), new_id()
    await client.put(f"/v1/riders/{other_rider}", json={"platform": "ios"})
    await client.put(f"/v1/bikes/{other_bike}", json={
        "rider_id": other_rider, "model": "Honda CB", "rated_top_speed_kmh": 150})
    body = await body_for(client, other_bike)
    r = await client.put(f"/v1/bikes/{bike['bike_id']}/model-checks/{new_id()}", json=body)
    assert r.status_code == 422


async def test_model_check_id_reused_by_other_bike(client, bike):
    cid = new_id()
    body = await body_for(client, bike["bike_id"])
    assert (await client.put(f"/v1/bikes/{bike['bike_id']}/model-checks/{cid}",
                             json=body)).status_code == 200
    other_rider, other_bike = new_id(), new_id()
    await client.put(f"/v1/riders/{other_rider}", json={"platform": "ios"})
    await client.put(f"/v1/bikes/{other_bike}", json={
        "rider_id": other_rider, "model": "Honda CB", "rated_top_speed_kmh": 150})
    body2 = await body_for(client, other_bike)
    r = await client.put(f"/v1/bikes/{other_bike}/model-checks/{cid}", json=body2)
    assert r.status_code == 409
