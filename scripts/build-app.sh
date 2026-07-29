#!/bin/bash
# PasteDeck.app をビルドする（フル Xcode 不要・Command Line Tools のみで動作）
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> リリースビルド"
swift build -c release --product PasteDeck

APP="build/PasteDeck.app"
echo "==> ${APP} を作成"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PasteDeck "$APP/Contents/MacOS/PasteDeck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 署名"
codesign --force --sign - "$APP"

echo "==> 完了: $APP"
echo "    open $APP で起動できます"
