#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"
TARGET_APP="/Applications/cduyzhShot.app"
STAGING_APP="/Applications/.cduyzhShot.installing"
BACKUP_APP="/Applications/.cduyzhShot.previous"
LS_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# 构建失败时保留当前安装；替换失败时恢复上一份。
echo "===> [1/5] 准备并验证新版本..."
./build_app.sh
SOURCE_APP="$PROJECT_DIR/.build.noindex/cduyzhShot.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_APP/Contents/Info.plist")"
if [ -e "$STAGING_APP" ] || [ -e "$BACKUP_APP" ]; then
    echo "发现上次安装的暂存目录，请先检查：$STAGING_APP / $BACKUP_APP" >&2
    exit 1
fi
/usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"

restore_on_failure() {
    local result=$?
    trap - EXIT
    if [ "$result" -ne 0 ] && [ -d "$BACKUP_APP" ]; then
        rm -rf "$TARGET_APP"
        mv "$BACKUP_APP" "$TARGET_APP"
        "$LS_REGISTER" -f "$TARGET_APP" 2>/dev/null || true
        echo "安装失败，已恢复上一版本。" >&2
    fi
    rm -rf "$STAGING_APP"
    exit "$result"
}
trap restore_on_failure EXIT

echo "===> [2/5] 退出产品进程..."
python3 - "$TARGET_APP" "$PROJECT_DIR" <<'PY'
import os
import signal
import subprocess
import sys
import time

target, root = sys.argv[1:]
owned = {
    target + "/Contents/MacOS/cduyzhShot",
    "/Applications/macShot.app/Contents/MacOS/macShot",
    root + "/.build.noindex/cduyzhShot.app/Contents/MacOS/cduyzhShot",
    root + "/build/cduyzhShot.app/Contents/MacOS/cduyzhShot",
    root + "/build/macShot.app/Contents/MacOS/macShot",
    root + "/.build/UIPreview/cduyzhShotPreview.app/Contents/MacOS/cduyzhShot",
}
processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
pids = []
for line in processes.splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and parts[1] in owned:
        pids.append(int(parts[0]))
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
for _ in range(50):
    remaining = []
    for pid in pids:
        try:
            os.kill(pid, 0)
            remaining.append(pid)
        except ProcessLookupError:
            pass
    if not remaining:
        break
    time.sleep(0.1)
else:
    raise SystemExit("应用尚未退出，已停止安装以保留当前任务。")
PY

echo "===> [3/5] 替换正式安装..."
if [ -d "$TARGET_APP" ]; then
    "$LS_REGISTER" -u "$TARGET_APP" 2>/dev/null || true
    mv "$TARGET_APP" "$BACKUP_APP"
fi
mv "$STAGING_APP" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
"$LS_REGISTER" -f "$TARGET_APP"

echo "===> [4/5] 移除旧副本的应用注册..."
for obsolete in "/Applications/macShot.app" "$PROJECT_DIR/build/macShot.app" "$PROJECT_DIR/build/cduyzhShot.app" "$PROJECT_DIR/.build/UIPreview/cduyzhShotPreview.app"; do
    if [ -d "$obsolete" ]; then
        "$LS_REGISTER" -u "$obsolete" 2>/dev/null || true
        rm -rf "$obsolete"
    fi
done
"$LS_REGISTER" -u "$SOURCE_APP" 2>/dev/null || true
rmdir "$PROJECT_DIR/build" 2>/dev/null || true
rm -rf "$BACKUP_APP"

echo "===> [5/5] 安装成功：cduyzhShot ${VERSION}（构建 ${BUILD}）"
echo "唯一正式入口：$TARGET_APP"
echo "菜单 → 更新记录，或设置 → 关于与更新，可核对当前版本。"
