"""Refresh only the explicit desktop payload in the checked-in prebuilt manifest."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2] / 'smoke/prebuilt'
manifest = json.loads((root / 'manifest.json').read_text())
files = manifest['files']
prefix = 'tools/smoke-bake/python/'
files = {name: entry for name, entry in files.items() if not name.startswith(prefix)}
payload = [root / name for name in ('CoD2SmokeTool.exe', 'DESKTOP-TOOL.txt', 'Smoke-Test.ps1', 'READ-ME-FIRST.txt', 'TESTING-NOTES.txt', 'licenses/LICENSE-LibreBaskerville.txt', 'licenses/LICENSE-Barlow.txt')]
payload += [p for p in (root / prefix).rglob('*') if p.is_file()]
for path in payload:
    if path.is_symlink():
        raise ValueError(f'Linked payload: {path}')
    data = path.read_bytes()
    files[path.relative_to(root).as_posix()] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
manifest['files'] = dict(sorted(files.items()))
(root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
lines = [f"{entry['sha256']}  {name}" for name, entry in manifest['files'].items()]
lines += [hashlib.sha256((root / 'manifest.json').read_bytes()).hexdigest() + '  manifest.json']
(root / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(f'Updated snapshot: {len(files)} files.')
