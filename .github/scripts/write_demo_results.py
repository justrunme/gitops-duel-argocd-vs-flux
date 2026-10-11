#!/usr/bin/env python3
"""Build docs/results.json from docs/bench-raw/* summaries (preferred) or results.md.

CI artifact upload fails closed when these files are missing.
"""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

ROOT = Path(".")
RAW = ROOT / "docs" / "bench-raw"
OUT = ROOT / "docs" / "results.json"
MD = ROOT / "docs" / "results.md"

PROFILE_INTERVALS = {
    "equal-10s": {
        "argocd_reconciliation": "10s",
        "flux_interval": "10s",
        "notes": "Equal polling/reconcile interval for a fair head-to-head.",
    },
    "defaults": {
        "argocd_reconciliation": "180s",
        "flux_interval": "1m",
        "notes": (
            "Argo stock timeout.reconciliation=180s; Flux interval=1m is a CI-bounded "
            "stand-in (stock Flux Kustomization default is 10m)."
        ),
    },
}


def load_from_raw() -> dict | None:
    if not RAW.is_dir():
        return None
    profiles: dict = {}
    for path in sorted(RAW.glob("*-argocd.json")):
        profile = path.name[: -len("-argocd.json")]
        flux_path = RAW / f"{profile}-flux.json"
        if not flux_path.is_file():
            continue
        profiles[profile] = {
            "intervals": PROFILE_INTERVALS.get(profile, {}),
            "metrics": {
                "Argo CD": json.loads(path.read_text()),
                "Flux": json.loads(flux_path.read_text()),
            },
        }
    if not profiles:
        return None
    return profiles


def load_from_markdown() -> dict:
    """Fallback parser for older single-table results.md."""
    text = MD.read_text(errors="replace") if MD.is_file() else ""
    rows = {}
    for line in text.splitlines():
        m = re.match(
            r"\|\s*(Argo CD|Flux)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|",
            line,
        )
        if not m:
            continue
        tool, ready, heal, rollback = (x.strip() for x in m.groups())
        rows[tool] = {
            "time_to_ready_seconds": {"median": ready, "min": ready, "max": ready, "samples": [ready], "n": 1},
            "time_to_self_heal_seconds": {"median": heal, "min": heal, "max": heal, "samples": [heal], "n": 1},
            "time_to_deletion_recovery_seconds": {
                "median": rollback,
                "min": rollback,
                "max": rollback,
                "samples": [rollback],
                "n": 1,
            },
        }
    return {
        "legacy": {
            "intervals": {},
            "metrics": rows,
        }
    }


def flatten_for_ci(profiles: dict) -> dict:
    """Keep top-level metrics for equal-10s (or first profile) so older CI checks can adapt."""
    preferred = "equal-10s" if "equal-10s" in profiles else next(iter(profiles))
    flat = {}
    for tool, metrics in profiles[preferred]["metrics"].items():
        flat[tool] = {
            key: (val["median"] if isinstance(val, dict) and "median" in val else val)
            for key, val in metrics.items()
        }
    return preferred, flat


def main() -> None:
    profiles = load_from_raw() or load_from_markdown()
    preferred, flat = flatten_for_ci(profiles)
    payload = {
        "repo": "gitops-duel-argocd-vs-flux",
        "source_run": "https://github.com/%s/actions/runs/%s"
        % (os.environ.get("GITHUB_REPOSITORY", ""), os.environ.get("GITHUB_RUN_ID", "")),
        "measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "samples_per_metric": int(os.environ.get("BENCHMARK_SAMPLES", "3")),
        "primary_profile": preferred,
        "profiles": profiles,
        # Convenience flat medians for the primary profile (README / legacy consumers)
        "metrics": flat,
    }
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
