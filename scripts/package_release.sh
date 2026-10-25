#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
python3 scripts/release_metadata.py
APP_PATH="${1:-/Applications/SnapScreen.app}"
codesign --verify --deep --strict "$APP_PATH"
python3 - "$APP_PATH" <<'PY'
import datetime
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
record_path = pathlib.Path('Sources/cduyzhShot/Resources/ReleaseHistory.json')
record = json.loads(record_path.read_text())['releases'][0]
with (app / 'Contents/Info.plist').open('rb') as file:
    installed = plistlib.load(file)
if (installed['CFBundleShortVersionString'], installed['CFBundleVersion']) != (record['version'], record['build']):
    raise SystemExit('安装包版本与待发行记录不一致，停止打包。')
if json.loads((app / 'Contents/Resources/ReleaseHistory.json').read_text())['releases'][0] != record:
    raise SystemExit('安装包内的版本记录不一致，停止打包。')
output = pathlib.Path('dist') / f"{record['version']}-{record['build']}"
output.mkdir(parents=True, exist_ok=True)
archive = output / f"cduyzhShot-{record['version']}-build{record['build']}.zip"
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
shutil.copy2('CHANGELOG.md', output / 'CHANGELOG.md')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(output / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
manifest = {
    'name': 'cduyzhShot', 'version': record['version'], 'build': record['build'],
    'releaseDate': record['date'], 'buildDate': installed.get('CDUYZHBuildDate'),
    'archive': archive.name, 'sha256': digest, 'publication': 'local',
    'title': record['title'], 'highlights': record['highlights'],
}
(output / 'release.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(f'本地发行包：{archive.resolve()}')
print(f'SHA-256：{digest}')
PY
