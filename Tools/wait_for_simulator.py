"""Bound simctl's boot wait so a stuck runtime cannot consume the entire CI job."""
import os
import subprocess
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
log_path.parent.mkdir(parents=True, exist_ok=True)
with log_path.open("w") as log:
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "bootstatus", os.environ["UI_SIMULATOR_ID"], "-b"],
            stdout=log, stderr=subprocess.STDOUT, timeout=300,
        )
        status = result.returncode
    except subprocess.TimeoutExpired:
        print("::error::The iOS simulator did not finish booting within 5 minutes.")
        status = 1

if status:
    print("\n".join(log_path.read_text(errors="replace").splitlines()[-25:]))
raise SystemExit(status)
