"""Calibration models."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from .common import SpeedKmh, Strict, Vec3


# --------------------------------------------------------------- calibrations


class CalibrationIn(Strict):
    bike_id: UUID
    ride_id: UUID
    calibrated_at: AwareDatetime
    mount_up: Vec3
    mount_forward: Vec3
    gyro_bias: Vec3
    linear_accel_bias: Vec3
    lean_gain: Annotated[float, Field(ge=0.5, le=2)]
    forward_from_motion: bool
    straight_offset_deg: Annotated[float, Field(ge=-90, le=90)]
    quality: Annotated[float, Field(ge=0, le=1)]
    achieved_top_speed_kmh: SpeedKmh | None = None
    stop_time_s: Annotated[float, Field(gt=0, le=120)] | None = None
    stop_start_speed_kmh: SpeedKmh | None = None
    stop_distance_m: Annotated[float, Field(ge=0)] | None = None
    max_decel_mps2: Annotated[float, Field(ge=0, le=30)] | None = None
    skipped_tasks: Annotated[list[str], Field(max_length=10)] = []
    warnings: Annotated[list[str], Field(max_length=20)] = []

    @model_validator(mode="after")
    def _unit_axes(self) -> "CalibrationIn":
        for name in ("mount_up", "mount_forward"):
            v = getattr(self, name)
            norm = sum(c * c for c in v) ** 0.5
            if abs(norm - 1) > 0.02:
                raise ValueError(f"{name} must be a unit vector (|v|={norm:.3f})")
        dot = sum(a * b for a, b in zip(self.mount_up, self.mount_forward))
        if abs(dot) > 0.02:
            raise ValueError("mount_up and mount_forward must be perpendicular")
        return self


class CalibrationOut(BaseModel):
    id: UUID
    bike_id: UUID
    ride_id: UUID
    calibrated_at: datetime
    mount_up: list[float]
    mount_forward: list[float]
    lean_gain: float
    forward_from_motion: bool
    straight_offset_deg: float
    quality: float
    achieved_top_speed_kmh: float | None
    stop_time_s: float | None
    max_decel_mps2: float | None
    warnings: list[str]
