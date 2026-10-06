#!/usr/bin/env python3
"""Check that config replay preserves local JSON state without hiding other drift."""

import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


with tempfile.TemporaryDirectory(prefix="config-json-test-") as scratch:
    repo = Path(scratch) / "repo.json"
    live = Path(scratch) / "live.json"

    def run(check, expect_success=True):
        result = subprocess.run(
            ["bash", "-c", '''
set -euo pipefail
CHECK=$1 DRIFT=0
source "$2/scripts/lib/copy.sh"
copy_json_preserving_keys_required "$3" "$4" ssh_connections
printf 'drift=%s\n' "$DRIFT"
''', "config-json-test", str(check), str(ROOT), str(repo), str(live)],
            capture_output=True, text=True,
        )
        assert (result.returncode == 0) == expect_success, result.stderr
        return result.stdout

    repo.write_text(json.dumps({"vim_mode": True, "tab_size": 4}))
    connections = [{"host": "home", "projects": [{"paths": ["/home/andres/code"]}]}]
    live.write_text(json.dumps({"ssh_connections": connections, "tab_size": 4, "vim_mode": True}))
    before = live.read_bytes()
    assert run(1) == "drift=0\n"
    assert live.read_bytes() == before
    assert run(0) == "drift=0\n"
    assert live.read_bytes() == before

    live.write_text(json.dumps({"ssh_connections": connections, "tab_size": 2, "vim_mode": True}))
    before = live.read_bytes()
    output = run(1)
    assert "drift=1" in output and '"tab_size": 4' in output
    assert live.read_bytes() == before
    assert "Updated" in run(0)
    assert json.loads(live.read_text()) == {"ssh_connections": connections, "tab_size": 4, "vim_mode": True}
    assert run(1) == "drift=0\n"

    # Invalid live state must stop replay without destroying local data.
    live.write_text("{broken")
    before = live.read_bytes()
    run(0, expect_success=False)
    assert live.read_bytes() == before

    live.unlink()
    assert "missing" in run(1)
    assert not live.exists()
    run(0)
    assert json.loads(live.read_text()) == json.loads(repo.read_text())

print("config JSON tests passed")
