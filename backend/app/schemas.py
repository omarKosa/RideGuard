"""Request/response models. Validation mirrors the database CHECK constraints
so bad data is rejected with a readable 422 before it reaches Postgres."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

Vec3 = Annotated[list[float], Field(min_length=3, max_length=3)]
SpeedKmh = Annotated[float, Field(ge=0, le=500)]
LeanMagnitude = Annotated[float, Field(ge=0, le=90)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


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
