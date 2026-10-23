"""Incident models."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from .common import SpeedKmh, Strict


# ------------------------------------------------------------------ incidents

IncidentKind = Literal["crash", "wobble", "impact", "extreme_lean"]
IncidentOutcome = Literal[
    "pending", "warned", "cancelled", "called", "dialer_opened", "call_failed",
    "no_contact",
]


class IncidentIn(Strict):
    kind: IncidentKind
    detected_at: AwareDatetime
    speed_kmh: SpeedKmh
    lean_deg: Annotated[float, Field(ge=-90, le=90)]
    peak_accel_g: Annotated[float, Field(ge=0, le=100)] | None = None
    wobble_hz: Annotated[float, Field(gt=0, le=25)] | None = None
    wobble_rms: Annotated[float, Field(ge=0, le=100)] | None = None
    latitude: Annotated[float, Field(ge=-90, le=90)] | None = None
    longitude: Annotated[float, Field(ge=-180, le=180)] | None = None
    outcome: IncidentOutcome
    resolved_at: AwareDatetime | None = None
    false_alarm: bool = False

    @model_validator(mode="after")
    def _consistent(self) -> "IncidentIn":
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude and longitude must be sent together")
        if (self.kind == "crash") == (self.outcome == "warned"):
            raise ValueError(
                "crashes are pending or resolved; other incidents are 'warned'"
            )
        unresolved = self.outcome in ("pending", "warned")
        if unresolved != (self.resolved_at is None):
            raise ValueError(f"resolved_at does not match outcome '{self.outcome}'")
        if self.resolved_at is not None and self.resolved_at < self.detected_at:
            raise ValueError("resolved_at is before detected_at")
        if self.false_alarm and self.kind == "crash":
            raise ValueError("a crash cannot be marked as a false alarm")
        return self


class IncidentOut(BaseModel):
    id: UUID
    ride_id: UUID
    kind: str
    detected_at: datetime
    speed_kmh: float
    lean_deg: float
    peak_accel_g: float | None
    wobble_hz: float | None
    wobble_rms: float | None
    latitude: float | None
    longitude: float | None
    outcome: str
    resolved_at: datetime | None
    false_alarm: bool
