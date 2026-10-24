"""Ride, sample, stats and brake-event models."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from .common import LeanMagnitude, SpeedKmh, Strict
from .model_checks import Measured


# ---------------------------------------------------------------------- rides


class RideIn(Strict):
    bike_id: UUID
    kind: Literal["calibration", "ride"]
    started_at: AwareDatetime
    analysis_window_min: Annotated[int, Field(ge=5, le=60)]
    calibration_id: UUID | None = None


class SampleIn(Strict):
    seq: Annotated[int, Field(ge=0)]
    recorded_at: AwareDatetime
    speed_kmh: SpeedKmh
    speed_source: Literal["none", "gps", "deadReckoning", "stale"]
    lean_deg: Annotated[float, Field(ge=-90, le=90)]
    roll_rate_dps: Annotated[float, Field(ge=-2000, le=2000)]
    yaw_rate_dps: Annotated[float, Field(ge=-2000, le=2000)]
    forward_accel_mps2: Annotated[float, Field(ge=-100, le=100)]
    lateral_accel_mps2: Annotated[float, Field(ge=-100, le=100)]
    latitude: Annotated[float, Field(ge=-90, le=90)] | None = None
    longitude: Annotated[float, Field(ge=-180, le=180)] | None = None
    gps_accuracy_m: Annotated[float, Field(ge=0)] | None = None

    @model_validator(mode="after")
    def _coordinates_pair(self) -> "SampleIn":
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude and longitude must be sent together")
        return self


class SampleBatchIn(Strict):
    samples: Annotated[list[SampleIn], Field(min_length=1, max_length=2000)]

    @model_validator(mode="after")
    def _unique_seq(self) -> "SampleBatchIn":
        seqs = [s.seq for s in self.samples]
        if len(seqs) != len(set(seqs)):
            raise ValueError("duplicate seq numbers in batch")
        return self


class SampleBatchOut(BaseModel):
    received: int
    inserted: int
    duplicates: int


class StatsIn(Strict):
    max_speed_kmh: SpeedKmh
    max_lean_left_deg: LeanMagnitude
    max_lean_right_deg: LeanMagnitude
    max_stop_time_s: Annotated[float, Field(ge=0, le=120)]
    best_decel_mps2: Annotated[float, Field(ge=0, le=30)]
    brake_event_count: Annotated[int, Field(ge=0)]
    distance_m: Annotated[float, Field(ge=0)]
    moving_time_s: Annotated[float, Field(ge=0)]
    avg_moving_speed_kmh: SpeedKmh
    span_s: Annotated[float, Field(ge=0)]


class BrakeEventIn(Strict):
    started_at: AwareDatetime
    ended_at: AwareDatetime
    start_speed_kmh: Annotated[float, Field(gt=0, le=500)]
    duration_s: Annotated[float, Field(gt=0, le=120)]
    distance_m: Annotated[float, Field(ge=0)]
    peak_decel_mps2: Annotated[float, Field(ge=0, le=30)]

    @model_validator(mode="after")
    def _ordered(self) -> "BrakeEventIn":
        if self.ended_at < self.started_at:
            raise ValueError("ended_at is before started_at")
        return self


class HistogramIn(Strict):
    min: Annotated[float, Field(gt=0)]
    max: float
    counts: Annotated[list[Annotated[int, Field(ge=0)]], Field(max_length=100)]

    @model_validator(mode="after")
    def _ordered(self) -> "HistogramIn":
        if self.max <= self.min:
            raise ValueError("max must be greater than min")
        return self


class BandStatsIn(Strict):
    band: Literal["20-40", "40-60", "60-90", "90-120", "120+"]
    seconds: Annotated[int, Field(ge=0)]
    wobble_rms: HistogramIn
    wobble_hz: HistogramIn
    peak_g: HistogramIn


class SafetyStatsIn(Strict):
    """Normal riding as the phone saw it, and the thresholds it used."""

    riding_s: Annotated[int, Field(ge=0)]
    wobble_rms_p99: Annotated[float, Field(ge=0, le=100)] | None = None
    peak_g_p99: Annotated[float, Field(ge=0, le=100)] | None = None
    imu_hz: Annotated[float, Field(gt=0, le=1000)] | None = None
    wobble_threshold_rms: Annotated[float, Field(gt=0, le=100)]
    wobble_max_hz: Annotated[float, Field(ge=0, le=500)]
    impact_threshold_g: Annotated[float, Field(gt=0, le=100)]
    extreme_lean_deg: Annotated[float, Field(gt=0, le=90)]
    bands: Annotated[list[BandStatsIn], Field(max_length=5)] = []


class RideSummaryIn(Strict):
    status: Literal["completed", "aborted"]
    ended_at: AwareDatetime
    analysis_window_min: Annotated[int, Field(ge=5, le=60)]
    mount_realignments: Annotated[int, Field(ge=0)]
    sample_count: Annotated[int, Field(ge=0)]
    totals: StatsIn
    window: StatsIn
    brake_events: Annotated[list[BrakeEventIn], Field(max_length=5000)]
    safety_stats: SafetyStatsIn | None = None
    performance: Measured | None = None


class BrakeEventOut(BaseModel):
    started_at: datetime
    ended_at: datetime
    start_speed_kmh: float
    duration_s: float
    distance_m: float
    peak_decel_mps2: float


class RideOut(BaseModel):
    id: UUID
    bike_id: UUID
    calibration_id: UUID | None
    kind: str
    status: str
    started_at: datetime
    ended_at: datetime | None
    analysis_window_min: int
    mount_realignments: int | None
    reported_sample_count: int | None
    stored_sample_count: int
    max_speed_kmh: float | None
    max_lean_left_deg: float | None
    max_lean_right_deg: float | None
    max_stop_time_s: float | None
    best_decel_mps2: float | None
    brake_event_count: int | None
    distance_m: float | None
    moving_time_s: float | None
    avg_moving_speed_kmh: float | None
    window_stats: dict | None
    safety_stats: dict | None
    performance: dict | None
    brake_events: list[BrakeEventOut] = []


class WindowAnalysisOut(BaseModel):
    """Server-side recomputation over the last N minutes of raw samples."""

    ride_id: UUID
    window_min: int
    sample_count: int
    window_start: datetime | None
    window_end: datetime | None
    max_speed_kmh: float | None
    max_lean_left_deg: float | None
    max_lean_right_deg: float | None
    max_stop_time_s: float | None
    best_decel_mps2: float | None
    brake_event_count: int
