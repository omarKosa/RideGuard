import os

import pytest

from app.google_auth import (
    GoogleIdentity,
    GoogleNotConfigured,
    InvalidGoogleToken,
    verify_google_id_token,
)

from .conftest import new_id

TOKEN = "header.payload.signature-of-a-google-id-token"


def fake_verifier(sub="google-123", email="rider@example.com", name="Mona"):
    def verify(token: str) -> GoogleIdentity:
        if token != TOKEN:
            raise InvalidGoogleToken("bad")
        return GoogleIdentity(sub=sub, email=email, name=name)

    return verify


async def make_rider(client) -> str:
    rider = new_id()
    r = await client.put(f"/v1/riders/{rider}", json={"platform": "android"})
    assert r.status_code == 200
    return rider


async def test_links_google_account_to_rider(client):
    client.app.state.verify_google = fake_verifier()
    rider = await make_rider(client)

    r = await client.put(f"/v1/riders/{rider}/google", json={"id_token": TOKEN})
    assert r.status_code == 200, r.text
    assert r.json()["google_email"] == "rider@example.com"
    assert r.json()["google_name"] == "Mona"

    # Retried by the outbox: same result.
    again = await client.put(f"/v1/riders/{rider}/google", json={"id_token": TOKEN})
    assert again.status_code == 200
    assert (await client.get(f"/v1/riders/{rider}")).json()["google_email"] == (
        "rider@example.com"
    )
    # A later phone/platform update keeps the link.
    await client.put(f"/v1/riders/{rider}", json={"platform": "android"})
    assert (await client.get(f"/v1/riders/{rider}")).json()["google_name"] == "Mona"


async def test_account_moves_to_the_newest_install(client):
    client.app.state.verify_google = fake_verifier()
    old, new = await make_rider(client), await make_rider(client)
    await client.put(f"/v1/riders/{old}/google", json={"id_token": TOKEN})

    r = await client.put(f"/v1/riders/{new}/google", json={"id_token": TOKEN})
    assert r.status_code == 200
    assert (await client.get(f"/v1/riders/{old}")).json()["google_email"] is None
    assert (await client.get(f"/v1/riders/{new}")).json()["google_email"] == (
        "rider@example.com"
    )


async def test_invalid_token_is_rejected(client):
    client.app.state.verify_google = fake_verifier()
    rider = await make_rider(client)
    r = await client.put(
        f"/v1/riders/{rider}/google", json={"id_token": "x" * 40}
    )
    assert r.status_code == 401
    assert (await client.get(f"/v1/riders/{rider}")).json()["google_email"] is None


async def test_unknown_rider_is_404(client):
    client.app.state.verify_google = fake_verifier()
    r = await client.put(f"/v1/riders/{new_id()}/google", json={"id_token": TOKEN})
    assert r.status_code == 404


async def test_server_without_google_config_says_so(client):
    def not_configured(token):
        raise GoogleNotConfigured()

    client.app.state.verify_google = not_configured
    rider = await make_rider(client)
    r = await client.put(f"/v1/riders/{rider}/google", json={"id_token": TOKEN})
    assert r.status_code == 503


async def test_unverified_email_is_not_stored(client):
    client.app.state.verify_google = fake_verifier(email=None, name=None)
    rider = await make_rider(client)
    r = await client.put(f"/v1/riders/{rider}/google", json={"id_token": TOKEN})
    assert r.status_code == 200
    assert r.json()["google_email"] is None


async def test_bad_body_is_422(client):
    rider = await make_rider(client)
    r = await client.put(f"/v1/riders/{rider}/google", json={"id_token": "short"})
    assert r.status_code == 422
    r = await client.put(
        f"/v1/riders/{rider}/google", json={"id_token": TOKEN, "email": "x"}
    )
    assert r.status_code == 422


def test_real_verifier_refuses_without_client_ids(monkeypatch):
    monkeypatch.delenv("GOOGLE_CLIENT_IDS", raising=False)
    with pytest.raises(GoogleNotConfigured):
        verify_google_id_token(TOKEN)


def test_real_verifier_rejects_garbage(monkeypatch):
    monkeypatch.setenv("GOOGLE_CLIENT_IDS", "abc.apps.googleusercontent.com")
    # Malformed tokens fail before any network call.
    with pytest.raises(InvalidGoogleToken):
        verify_google_id_token("not-a-jwt")
    assert os.getenv("GOOGLE_CLIENT_IDS")


async def test_rider_sets_and_changes_their_name(client):
    rider = await make_rider(client)

    r = await client.put(f"/v1/riders/{rider}/name", json={"name": "  Omar   K "})
    assert r.status_code == 200, r.text
    assert r.json()["display_name"] == "Omar K"

    # The outbox may deliver it twice, or after a later phone update.
    await client.put(f"/v1/riders/{rider}/name", json={"name": "Omar K"})
    await client.put(f"/v1/riders/{rider}", json={"platform": "android"})
    assert (await client.get(f"/v1/riders/{rider}")).json()["display_name"] == "Omar K"

    await client.put(f"/v1/riders/{rider}/name", json={"name": "Omar"})
    assert (await client.get(f"/v1/riders/{rider}")).json()["display_name"] == "Omar"


async def test_rider_name_is_validated(client):
    rider = await make_rider(client)
    for bad in ("", "   ", "x" * 61):
        r = await client.put(f"/v1/riders/{rider}/name", json={"name": bad})
        assert r.status_code == 422, bad
    missing = await client.put(f"/v1/riders/{new_id()}/name", json={"name": "Omar"})
    assert missing.status_code == 404
