#!/usr/bin/env python3
import json, os, re, time
from pathlib import Path

text = Path("docs/results.md").read_text(errors="replace")
rows = {}
for line in text.splitlines():
    m = re.match(r"\|\s*(Argo CD|Flux)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|", line)
    if m:
        tool, ready, heal, rollback = (x.strip() for x in m.groups())
        rows[tool] = {
            "time_to_ready_seconds": ready,
            "time_to_self_heal_seconds": heal,
            "time_to_rollback_seconds": rollback,
        }
payload = {
    "repo": "gitops-duel-argocd-vs-flux",
    "source_run": "https://github.com/%s/actions/runs/%s"
    % (os.environ.get("GITHUB_REPOSITORY", ""), os.environ.get("GITHUB_RUN_ID", "")),
    "measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "metrics": rows,
}
Path("docs/results.json").write_text(json.dumps(payload, indent=2) + "\n")
print(json.dumps(payload, indent=2))
