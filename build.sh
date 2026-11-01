#!/bin/bash
# 빌드해서 build/RecMac.app 을 만든다.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RecMac"

APP="build/RecMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RecMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 서명: 키체인에 "MacRecorder Dev" 인증서가 있으면 그걸로 서명해서
# 다시 빌드해도 화면 녹화 권한이 유지되게 한다. 없으면 임시(ad-hoc) 서명.
SIGN_ID="MacRecorder Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" "$APP"
    echo "서명: $SIGN_ID"
else
    codesign --force --sign - "$APP"
    echo "서명: 임시(ad-hoc) — 다시 빌드하면 권한을 다시 허용해야 할 수 있어요"
fi

echo "빌드 완료: $APP"
if [ "${RECMAC_NO_OPEN:-0}" != "1" ]; then
    open "$APP"
fi
