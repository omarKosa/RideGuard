"""Init-ride model check models."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from .common import SpeedKmh, Strict

CheckResult = Literal["match", "mismatch", "not_tested"]


class Expected(Strict):
    top_speed_kmh: SpeedKmh | None = None
    max_accel_mps2: Annotated[float, Field(ge=0, le=100)] | None = None
    max_decel_mps2: Annotated[float, Field(ge=0, le=100)] | None = None


class Stop(Strict):
    start_speed_kmh: SpeedKmh
    duration_s: Annotated[float, Field(gt=0, le=120)]
    mean_decel_mps2: Annotated[float, Field(ge=0, le=100)]


class Measured(Strict):
    sustained_top_speed_kmh: SpeedKmh | None = None
    peak_accel_mps2: Annotated[float, Field(ge=0, le=100)] | None = None
    peak_decel_mps2: Annotated[float, Field(ge=0, le=100)] | None = None
    stops: Annotated[list[Stop], Field(max_length=50)] = []


class Results(Strict):
    top_speed: CheckResult
    acceleration: CheckResult
    braking: CheckResult


class ModelCheckIn(Strict):
    reason: Literal["init_ride", "model_corrected"]
    calibration_id: UUID
    ride_id: UUID
    checked_at: AwareDatetime
    catalogue_model_id: Annotated[str, Field(min_length=1, max_length=120)] | None = None
    catalogue_version: Annotated[str, Field(min_length=1, max_length=40)] | None = None
    other_make: Annotated[str, Field(min_length=1, max_length=40)] | None = None
    other_model: Annotated[str, Field(min_length=1, max_length=60)] | None = None
    other_year: Annotated[int, Field(ge=1950, le=2030)] | None = None
    phone_model: Annotated[str, Field(max_length=80)] | None = None
    imu_hz: Annotated[float, Field(gt=0, le=1000)] | None = None
    expected: Expected | None = None
    measured: Measured
    results: Results
    mismatch: bool

    @model_validator(mode="after")
    def _consistent(self) -> "ModelCheckIn":
        failing = "mismatch" in self.results.model_dump().values()
        if self.mismatch != failing:
            raise ValueError("mismatch must equal any(result == 'mismatch')")
        return self


class ModelCheckOut(BaseModel):
    id: UUID
    bike_id: UUID
    calibration_id: UUID
    ride_id: UUID
    reason: str
    catalogue_model_id: str | None
    catalogue_version: str | None
    other_make: str | None
    other_model: str | None
    other_year: int | None
    phone_model: str | None
    imu_hz: float | None
    expected: dict | None
    measured: dict
    results: dict
    mismatch: bool
    checked_at: datetime
    created_at: datetime
