"""Reuse compiler timestamps only when cached and current file contents are identical."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

manifest = Path('build/source-file-stamps.json')
try:
    old = json.loads(manifest.read_text())
except (OSError, ValueError):
    old = {}
if not isinstance(old, dict):
    old = {}
roots = ('Erhu/', 'ErhuTests/', 'ErhuInteractionTests/', 'ErhuPlayerWidget/', 'WidgetShared/', 'Support/')
tracked = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
files = [Path(name) for name in tracked if name.startswith(roots) or name == 'project.yml']
# XcodeGen recreates these files on checkout; identical generated projects should retain their build signature too.
files += list(Path('Erhu.xcodeproj').rglob('*.pbxproj'))
files += list(Path('Erhu.xcodeproj').rglob('*.xcscheme'))
current = {}
restored = 0
for path in files:
    if not path.is_file() or path.is_symlink():
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    record = old.get(str(path), {})
    if not isinstance(record, dict):
        record = {}
    if record.get('sha256') == digest and isinstance(record.get('mtime_ns'), int):
        stat = path.stat()
        os.utime(path, ns=(stat.st_atime_ns, record['mtime_ns']))
        restored += 1
    current[str(path)] = {'sha256': digest, 'mtime_ns': path.stat().st_mtime_ns}
manifest.parent.mkdir(parents=True, exist_ok=True)
manifest.write_text(json.dumps(current, sort_keys=True) + '\n')
print(f'Restored compiler timestamps for {restored} unchanged source/project files; changed files retain fresh timestamps.')
