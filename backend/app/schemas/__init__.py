"""Request/response models, split by area. Validation mirrors the database
CHECK constraints so bad data is rejected with a readable 422 before it
reaches Postgres. Everything is re-exported so `from ..schemas import X` works."""

from .calibrations import CalibrationIn, CalibrationOut
from .common import LeanMagnitude, SpeedKmh, Strict, Vec3
from .incidents import (
    ClipIn,
    IncidentIn,
    IncidentKind,
    IncidentOut,
    IncidentOutcome,
)
from .model_checks import ModelCheckIn, ModelCheckOut
from .riders import (
    BikeIn,
    BikeOut,
    BikeStatsOut,
    GoogleLinkIn,
    RiderIn,
    RiderOut,
)
from .rides import (
    BrakeEventIn,
    BrakeEventOut,
    RideIn,
    RideOut,
    RideSummaryIn,
    SafetyStatsIn,
    SampleBatchIn,
    SampleBatchOut,
    SampleIn,
    StatsIn,
    WindowAnalysisOut,
)

__all__ = [
    "GoogleLinkIn",
    "BikeIn", "BikeOut", "BikeStatsOut",
    "BrakeEventIn", "BrakeEventOut",
    "CalibrationIn", "CalibrationOut", "ClipIn",
    "IncidentIn", "IncidentKind", "IncidentOut", "IncidentOutcome",
    "LeanMagnitude", "ModelCheckIn", "ModelCheckOut",
    "RideIn", "RideOut", "RideSummaryIn", "RiderIn", "RiderOut",
    "SafetyStatsIn", "SampleBatchIn", "SampleBatchOut", "SampleIn",
    "SpeedKmh", "StatsIn", "Strict", "Vec3", "WindowAnalysisOut",
]
