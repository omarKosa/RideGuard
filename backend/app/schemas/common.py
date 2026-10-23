"""Shared validation primitives for the request/response models."""

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

Vec3 = Annotated[list[float], Field(min_length=3, max_length=3)]
SpeedKmh = Annotated[float, Field(ge=0, le=500)]
LeanMagnitude = Annotated[float, Field(ge=0, le=90)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")
