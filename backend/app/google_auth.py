"""Verifies Google ID tokens sent by the app after Google sign-in."""

import os
from dataclasses import dataclass

from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


class GoogleNotConfigured(Exception):
    """GOOGLE_CLIENT_IDS is not set, so no token can be trusted."""


class InvalidGoogleToken(Exception):
    pass


@dataclass(frozen=True)
class GoogleIdentity:
    sub: str
    email: str | None
    name: str | None


def allowed_audiences() -> list[str]:
    """OAuth client ids the tokens must be issued for (comma-separated)."""
    raw = os.getenv("GOOGLE_CLIENT_IDS", "")
    return [a.strip() for a in raw.split(",") if a.strip()]


def verify_google_id_token(token: str) -> GoogleIdentity:
    """Checks signature, expiry, issuer and audience. Blocking (fetches
    Google's public keys, cached by google-auth)."""
    audiences = allowed_audiences()
    if not audiences:
        raise GoogleNotConfigured()
    try:
        claims = id_token.verify_oauth2_token(
            token, google_requests.Request(), audience=audiences
        )
    except ValueError as exc:
        raise InvalidGoogleToken(str(exc)) from exc
    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise InvalidGoogleToken("wrong issuer")
    email = claims.get("email") if claims.get("email_verified") else None
    return GoogleIdentity(
        sub=str(claims["sub"]), email=email, name=claims.get("name")
    )
