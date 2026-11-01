#!/bin/bash
# 서명된 앱과 Applications 바로가기가 담긴 배포용 DMG를 만든다.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/RecMac.app"
DMG="build/RecMac.dmg"
if [ ! -d "$APP" ]; then
    echo "앱이 없습니다. 먼저 ./build.sh 를 실행하세요." >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/RecMac.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname RecMac -srcfolder "$STAGING" -ov -format UDZO "$DMG"
echo "DMG 생성: $DMG"
