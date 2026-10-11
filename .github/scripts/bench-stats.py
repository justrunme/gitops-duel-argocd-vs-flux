#!/usr/bin/env python3
"""Aggregate benchmark sample CSV into median/min/max JSON fragments."""
from __future__ import annotations

import json
import sys
from statistics import median


def parse_samples(lines: list[str]) -> dict[str, list[float]]:
    # each line: ready,heal,rollback,commit_ready
    keys = [
        "time_to_ready_seconds",
        "time_to_self_heal_seconds",
        "time_to_deletion_recovery_seconds",
        "time_to_commit_ready_seconds",
    ]
    buckets = {k: [] for k in keys}
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) != 4:
            raise SystemExit(f"expected 4 CSV fields, got {line!r}")
        for key, raw in zip(keys, parts):
            try:
                buckets[key].append(float(raw))
            except ValueError as exc:
                raise SystemExit(f"non-numeric {key}={raw!r}") from exc
    return buckets


def summarize(values: list[float]) -> dict:
    if not values:
        raise SystemExit("no samples")
    return {
        "median": f"{median(values):.3f}",
        "min": f"{min(values):.3f}",
        "max": f"{max(values):.3f}",
        "samples": [f"{v:.3f}" for v in values],
        "n": len(values),
    }


def main() -> None:
    lines = sys.stdin.read().splitlines()
    buckets = parse_samples(lines)
    out = {k: summarize(v) for k, v in buckets.items()}
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
