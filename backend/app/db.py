"""Connection pool and schema migrations."""

import json
import logging
from pathlib import Path

import asyncpg

log = logging.getLogger(__name__)

MIGRATIONS_DIR = Path(__file__).parent / "migrations"
# Arbitrary constant: serialises migrations when several API replicas start.
_MIGRATION_LOCK = 724_151_001


async def _init_connection(conn: asyncpg.Connection) -> None:
    for name in ("json", "jsonb"):
        await conn.set_type_codec(
            name, encoder=json.dumps, decoder=json.loads, schema="pg_catalog"
        )


async def create_pool(dsn: str) -> asyncpg.Pool:
    return await asyncpg.create_pool(
        dsn, min_size=1, max_size=10, init=_init_connection, command_timeout=30
    )


async def migrate(pool: asyncpg.Pool) -> list[str]:
    """Applies pending migrations in filename order. Returns applied names."""
    applied: list[str] = []
    async with pool.acquire() as conn:
        await conn.execute("SELECT pg_advisory_lock($1)", _MIGRATION_LOCK)
        try:
            await conn.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    name        text PRIMARY KEY,
                    applied_at  timestamptz NOT NULL DEFAULT now()
                )
                """
            )
            done = {
                r["name"] for r in await conn.fetch("SELECT name FROM schema_migrations")
            }
            for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
                if path.name in done:
                    continue
                async with conn.transaction():
                    await conn.execute(path.read_text())
                    await conn.execute(
                        "INSERT INTO schema_migrations (name) VALUES ($1)", path.name
                    )
                log.info("Applied migration %s", path.name)
                applied.append(path.name)
        finally:
            await conn.execute("SELECT pg_advisory_unlock($1)", _MIGRATION_LOCK)
    return applied
