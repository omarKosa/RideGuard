"""Rider and bike models."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, Field

from .calibrations import CalibrationOut
from .common import Strict


# --------------------------------------------------------------------- riders


class RiderIn(Strict):
    platform: Annotated[str, Field(max_length=32)] | None = None


class RiderOut(BaseModel):
    id: UUID
    platform: str | None
    created_at: datetime


# ---------------------------------------------------------------------- bikes


class BikeIn(Strict):
    rider_id: UUID
    model: Annotated[str, Field(min_length=2, max_length=80)]
    rated_top_speed_kmh: Annotated[float, Field(ge=40, le=420)]


class BikeOut(BaseModel):
    id: UUID
    rider_id: UUID
    model: str
    rated_top_speed_kmh: float
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
