"""Catalogue maintenance reports: `python -m app.reports gaps|mismatches`."""

import asyncio
import json
import os
import sys
from typing import Literal

import asyncpg

VIEWS = {"gaps": "catalogue_gaps", "mismatches": "catalogue_mismatches"}
ORDER = {"gaps": "bikes DESC, model", "mismatches": "mismatches DESC, catalogue_model_id"}


async def fetch_report(conn, name: Literal["gaps", "mismatches"]) -> list[dict]:
    if name not in VIEWS:
        raise ValueError(f"unknown report '{name}'")
    rows = await conn.fetch(f"SELECT * FROM {VIEWS[name]} ORDER BY {ORDER[name]}")
    return [dict(r) for r in rows]


def _cell(v) -> str:
    if v is None:
        return ""
    if isinstance(v, (dict, list)):
        return json.dumps(v, separators=(",", ":"))
    return str(v)


def format_table(rows: list[dict], columns: list[str]) -> str:
    cells = [[_cell(r.get(c)) for c in columns] for r in rows]
    widths = [max([len(c)] + [len(row[i]) for row in cells]) for i, c in enumerate(columns)]
    line = lambda vals: "  ".join(v.ljust(w) for v, w in zip(vals, widths)).rstrip()
    return "\n".join([line(columns), line(["-" * w for w in widths])] + [line(r) for r in cells])


async def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in VIEWS:
        print("usage: python -m app.reports gaps|mismatches", file=sys.stderr)
        return 2
    conn = await asyncpg.connect(os.environ["DATABASE_URL"])
    try:
        # Column names come from the view itself, so an empty report still
        # prints its header.
        cols = [a.name for a in (await conn.prepare(
            f"SELECT * FROM {VIEWS[argv[0]]}")).get_attributes()]
        rows = await fetch_report(conn, argv[0])
    finally:
        await conn.close()
    print(format_table(rows, cols))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main(sys.argv[1:])))
