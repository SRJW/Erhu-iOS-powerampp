"""Publish test identifiers and fixed runner categories, without exposing raw logs."""
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("Native interaction checks have not run.")
    raise SystemExit(0)
log = path.read_text(errors="replace")
states = {}
classic = re.compile(r"Test Case '-\[(?:ErhuInteractionTests\.)?(LibraryInteractionTests) (test[A-Za-z0-9_]+)\]' (started|passed|failed)")
compact = re.compile(r"Test case '(LibraryInteractionTests)\.(test[A-Za-z0-9_]+)\(\)' (passed|failed)")
for pattern in [classic, compact]:
    for name, method, state in pattern.findall(log):
        states[name + "." + method] = state
categories = ["XCTDaemonErrorDomain", "Failed to initialize", "Timed out waiting for", "Early unexpected exit", "SIGABRT", "SIGSEGV"]
# A Debug-only compilation error can stop xcodebuild before the first test starts.
# Report compiler diagnostics as well as test identifiers; do not dump raw logs or
# the runner's environment/command lines into annotations.
compiler = re.compile(r"(?:^|/)[^/\s]+\.(?:swift|m|mm|h):\d+(?::\d+)?:\s*(?:fatal )?error:.*")
diagnostics = list(dict.fromkeys(match.group(0) for line in log.splitlines()
                                 if (match := compiler.search(line))))[:20]
lines = ["Native interaction results:"]
if not states:
    lines.append("No individual test results were reported; the test suite is not validated.")
lines += diagnostics
lines += [name + ": " + state for name, state in states.items()]
lines += ["Runner category: " + category for category in categories if category.lower() in log.lower()]
fractions = re.findall(r"Chrome fraction after list scrolling: ([0-9.]+)", log)
if fractions:
    lines.append("Chrome fraction: " + fractions[-1])
summary = "\n".join(lines)
print("::notice::" + summary.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A"))

for diagnostic in diagnostics:
    print("::error::" + diagnostic.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A"))
