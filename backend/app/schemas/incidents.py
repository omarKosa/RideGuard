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


# One IMU sample: [t, x, y, z].
Row = Annotated[list[float], Field(min_length=4, max_length=4)]


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
    rider_label: Literal["yes", "no"] | None = None
    labelled_at: AwareDatetime | None = None
    # Deprecated: sent by app versions before rider labels, still queued in
    # riders' outboxes. True on a warning (never a crash) without a label
    # means the rider said "not real"; otherwise it is ignored.
    false_alarm: bool | None = None

    @model_validator(mode="after")
    def _consistent(self) -> "IncidentIn":
        if self.false_alarm and self.kind != "crash" and self.rider_label is None:
            self.rider_label = "no"
            self.labelled_at = self.resolved_at or self.detected_at
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
        if (self.rider_label is None) != (self.labelled_at is None):
            raise ValueError("rider_label and labelled_at must be sent together")
        if self.labelled_at is not None and self.labelled_at < self.detected_at:
            raise ValueError("labelled_at is before detected_at")
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
    rider_label: str | None
    labelled_at: datetime | None
    false_alarm: bool


class ClipIn(Strict):
    rate_hz: Annotated[float, Field(gt=0, le=1000)]
    start_offset_s: Annotated[float, Field(ge=-10, le=0)]
    accel: Annotated[list[Row], Field(max_length=1500)]
    gyro: Annotated[list[Row], Field(max_length=1500)]
