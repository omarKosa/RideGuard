"""Loads the shipped bike catalogue into the catalogue_models table."""

from pathlib import Path

import asyncpg

from .catalogue_schema import CATALOGUE_PATH, load_catalogue


def _v(spec) -> float | None:
    return None if spec is None else spec.value


async def sync_catalogue(pool: asyncpg.Pool, path: Path = CATALOGUE_PATH) -> int:
    """Upserts every model in the file, deletes rows no longer in it.
    Returns the number of models in the file."""
    cat = load_catalogue(path)
    rows = [
        (
            m.id, cat.version, m.make, m.model, m.year_from, m.year_to,
            list(m.markets), m.category, m.abs, _v(m.displacement_cc),
            _v(m.power_kw), _v(m.weight_kg), _v(m.top_speed_kmh),
            _v(m.zero_to_100_s), m.model_dump(mode="json"),
        )
        for m in cat.models
    ]
    async with pool.acquire() as conn, conn.transaction():
        await conn.executemany(
            """
            INSERT INTO catalogue_models
                (id, catalogue_version, make, model, year_from, year_to,
                 markets, category, abs, displacement_cc, power_kw, weight_kg,
                 top_speed_kmh, zero_to_100_s, spec)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
            ON CONFLICT (id) DO UPDATE SET
                catalogue_version = EXCLUDED.catalogue_version,
                make = EXCLUDED.make, model = EXCLUDED.model,
                year_from = EXCLUDED.year_from, year_to = EXCLUDED.year_to,
                markets = EXCLUDED.markets, category = EXCLUDED.category,
                abs = EXCLUDED.abs, displacement_cc = EXCLUDED.displacement_cc,
                power_kw = EXCLUDED.power_kw, weight_kg = EXCLUDED.weight_kg,
                top_speed_kmh = EXCLUDED.top_speed_kmh,
                zero_to_100_s = EXCLUDED.zero_to_100_s,
                spec = EXCLUDED.spec, updated_at = now()
            """,
            rows,
        )
        await conn.execute(
            "DELETE FROM catalogue_models WHERE id <> ALL($1::text[])",
            [m.id for m in cat.models],
        )
    return len(rows)
