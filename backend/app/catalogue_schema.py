"""Shape of the bike catalogue (app/catalogue/bikes.json).

Every spec value carries the URL it came from and how trustworthy that
source is; a value nobody could verify is null, never estimated."""

from pathlib import Path
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator

CATALOGUE_PATH = Path(__file__).parent / "catalogue" / "bikes.json"

Quality = Literal["official", "road_test", "aggregator"]
Category = Literal[
    "scooter", "commuter", "naked", "sport", "touring", "adventure",
    "cruiser", "off_road",
]
Abs = Literal["yes", "no", "optional", "unknown"]
Market = Literal["tr", "sa"]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SpecValue(_Strict):
    value: float
    source: HttpUrl
    quality: Quality


class WeightValue(SpecValue):
    basis: Literal["wet", "kerb", "dry"]


# Plausible ranges for each spec; a value outside is a data-entry error.
class Displacement(SpecValue):
    value: Annotated[float, Field(ge=49, le=2500)]


class Power(SpecValue):
    value: Annotated[float, Field(ge=1, le=250)]


class Weight(WeightValue):
    value: Annotated[float, Field(ge=60, le=450)]


class TopSpeed(SpecValue):
    value: Annotated[float, Field(ge=40, le=420)]


class ZeroTo100(SpecValue):
    value: Annotated[float, Field(ge=2.3, le=30)]


class CatalogueModel(_Strict):
    id: Annotated[str, Field(pattern=r"^[a-z0-9-]+$")]
    make: Annotated[str, Field(min_length=1)]
    model: Annotated[str, Field(min_length=1)]
    year_from: Annotated[int, Field(ge=1990, le=2027)]
    year_to: Annotated[int, Field(ge=1990, le=2027)] | None
    markets: Annotated[list[Market], Field(min_length=1)]
    category: Category
    abs: Abs
    displacement_cc: Displacement
    power_kw: Power | None
    weight_kg: Weight | None
    top_speed_kmh: TopSpeed | None
    zero_to_100_s: ZeroTo100 | None

    @model_validator(mode="after")
    def _check(self) -> "CatalogueModel":
        if self.year_to is not None and self.year_to < self.year_from:
            raise ValueError("year_to must be >= year_from")
        if len(set(self.markets)) != len(self.markets):
            raise ValueError("markets must not repeat")
        return self


class Catalogue(_Strict):
    version: Annotated[str, Field(min_length=1)]
    make_order: Annotated[list[str], Field(min_length=1)]
    models: Annotated[list[CatalogueModel], Field(min_length=1)]

    @model_validator(mode="after")
    def _check(self) -> "Catalogue":
        ids = [m.id for m in self.models]
        if len(ids) != len(set(ids)):
            raise ValueError("model ids must be unique")
        if len(self.make_order) != len(set(self.make_order)):
            raise ValueError("make_order must not repeat a make")
        if set(self.make_order) != {m.make for m in self.models}:
            raise ValueError("make_order must list exactly the makes used")
        return self


def load_catalogue(path: Path = CATALOGUE_PATH) -> Catalogue:
    """Parse and validate the catalogue file."""
    return Catalogue.model_validate_json(path.read_bytes())
