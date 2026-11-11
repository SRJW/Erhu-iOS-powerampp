"""Record current xcresult counts and reject empty or failed CI test runs."""
import json
import os
import subprocess
import sys
from pathlib import Path

failed = False
for argument in sys.argv[1:]:
    bundle = Path(argument)
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        print(f"::error::Cannot read test results for {bundle.name}: {result.stderr}")
        failed = True
        continue
    data = json.loads(result.stdout)
    bundle.with_suffix(".summary.json").write_text(json.dumps(data, indent=2) + "\n")
    total, failures = data["totalTestCount"], data["failedTests"]
    message = (f"{bundle.name}: {total} tests; {data['passedTests']} passed; "
               f"{failures} failed; {data['skippedTests']} skipped")
    print("::notice::" + message)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(message + "\n\n")
    if total <= 0 or failures:
        print("::error::" + message)
        failed = True
raise SystemExit(1 if failed else 0)
