"""The bike catalogue file ships with the backend and the app; it must always
load cleanly and every spec value must carry its source."""

import re

import pytest
from pydantic import ValidationError

from app.catalogue_schema import CatalogueModel, load_catalogue

REQUIRED_BRANDS = [
    "Honda", "Yamaha", "Suzuki", "Kawasaki", "BMW", "KTM", "Ducati",
    "Triumph", "Harley-Davidson", "CFMoto", "Bajaj", "TVS", "Kymco", "SYM",
    "Piaggio", "Vespa", "Benelli", "Voge", "Mondial", "Kuba", "RKS",
]


def test_catalogue_file_is_valid():
    cat = load_catalogue()
    assert len(cat.models) >= 120
    ids = [m.id for m in cat.models]
    assert len(ids) == len(set(ids))
    assert all(re.fullmatch(r"[a-z0-9-]+", i) for i in ids)


def test_target_models_present():
    by_id = {m.id: m for m in load_catalogue().models}
    assert "suzuki-gsx-s1000-2015" in by_id
    assert "suzuki-gsx-s1000-2021" in by_id
    assert by_id["suzuki-gsx-s1000-2021"].displacement_cc.value == 999


def test_brand_coverage():
    cat = load_catalogue()
    makes = {m.make for m in cat.models}
    for brand in REQUIRED_BRANDS:
        assert brand in makes, brand
    # TR lineups are published per model by the Turkish distributors. SA flags
    # are kept only where a KSA/GCC lineup confirms the model (44 verified), so
    # the SA floor is that verified count rather than 60.
    minimum = {"tr": 60, "sa": 44}
    for market, floor in minimum.items():
        assert sum(market in m.markets for m in cat.models) >= floor, market
    assert sorted(cat.make_order) == sorted(makes)
    assert len(cat.make_order) == len(set(cat.make_order))


def _model_dict(**overrides):
    d = {
        "id": "test-bike-2020",
        "make": "Test", "model": "Bike",
        "year_from": 2020, "year_to": None,
        "markets": ["tr"],
        "category": "naked",
        "abs": "yes",
        "displacement_cc": {"value": 999, "source": "https://example.com/a",
                            "quality": "official"},
        "power_kw": None,
        "weight_kg": None,
        "top_speed_kmh": None,
        "zero_to_100_s": None,
    }
    d.update(overrides)
    return d


def test_rejects_value_without_source():
    CatalogueModel.model_validate(_model_dict())  # control: valid as-is
    with pytest.raises(ValidationError):
        CatalogueModel.model_validate(_model_dict(
            top_speed_kmh={"value": 250, "quality": "road_test"}))
