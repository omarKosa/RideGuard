"""Rider and bike models."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

from .calibrations import CalibrationOut
from .common import Strict


# --------------------------------------------------------------------- riders


class RiderIn(Strict):
    platform: Annotated[str, Field(max_length=32)] | None = None
    phone_model: Annotated[str, Field(max_length=80)] | None = None
    os_version: Annotated[str, Field(max_length=40)] | None = None


class RiderOut(BaseModel):
    id: UUID
    platform: str | None
    phone_model: str | None
    os_version: str | None
    google_email: str | None = None
    google_name: str | None = None
    display_name: str | None = None
    created_at: datetime


class GoogleLinkIn(Strict):
    """The ID token from Google sign-in on the phone."""

    id_token: Annotated[str, Field(min_length=20, max_length=4096)]


class RiderNameIn(Strict):
    """The name the rider typed. Whitespace-only is rejected."""

    name: Annotated[str, Field(min_length=1, max_length=60)]

    @field_validator("name")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("name must not be blank")
        return v


# ---------------------------------------------------------------------- bikes


TopSpeedSource = Literal["catalogue", "rider", "measured"]


class BikeIn(Strict):
    rider_id: UUID
    model: Annotated[str, Field(min_length=2, max_length=80)]
    rated_top_speed_kmh: Annotated[float, Field(ge=40, le=420)]
    catalogue_model_id: Annotated[str, Field(min_length=1, max_length=120)] | None = None
    catalogue_version: Annotated[str, Field(min_length=1, max_length=40)] | None = None
    other_make: Annotated[str, Field(min_length=1, max_length=40)] | None = None
    other_model: Annotated[str, Field(min_length=1, max_length=60)] | None = None
    other_year: Annotated[int, Field(ge=1950, le=2030)] | None = None
    top_speed_source: TopSpeedSource = "rider"

    @model_validator(mode="after")
    def _catalogue_xor_other(self) -> "BikeIn":
        if self.catalogue_model_id is not None and (
            self.other_make is not None or self.other_model is not None
        ):
            raise ValueError(
                "catalogue_model_id and other_make/other_model are mutually exclusive"
            )
        return self


class BikeOut(BaseModel):
    id: UUID
    rider_id: UUID
    model: str
    rated_top_speed_kmh: float
    catalogue_model_id: str | None
    catalogue_version: str | None
    other_make: str | None
    other_model: str | None
    other_year: int | None
    top_speed_source: str
    created_at: datetime


class BikeStatsOut(BaseModel):
    bike_id: UUID
    ride_count: int
    total_distance_m: float
    max_speed_kmh: float | None
    max_lean_left_deg: float | None
    max_lean_right_deg: float | None
    max_stop_time_s: float | None
    best_decel_mps2: float | None
    latest_calibration: CalibrationOut | None
