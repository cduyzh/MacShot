#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"
# Keep a macOS 14 deployment baseline even when the build host uses macOS 27.
export MACOSX_DEPLOYMENT_TARGET=14.0
python3 scripts/release_metadata.py

echo "===> [1/4] 编译 Release..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/.build.noindex/SnapScreen.app"
mkdir -p "$PROJECT_DIR/.build.noindex"
touch "$PROJECT_DIR/.build.noindex/.metadata_never_index"

echo "===> [2/4] 打包应用与版本记录..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/cduyzhShot" "$APP_DIR/Contents/MacOS/cduyzhShot"
cp Info.plist "$APP_DIR/Contents/Info.plist"
cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
python3 scripts/release_metadata.py --stamp-bundle "$APP_DIR"

echo "===> [3/4] 固定应用标识并验证签名..."
codesign --force --sign - --requirements '=designated => identifier "com.cduyzh.shot"' --entitlements cduyzhShot.entitlements "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "===> [4/4] 已生成 $APP_DIR"
