#!/bin/bash
# 확정된 SVG에서 macOS 앱 아이콘을 생성한다.
set -euo pipefail
cd "$(dirname "$0")"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "${ICONSET%/AppIcon.iconset}"' EXIT

sips -s format png web-design/recmac-app-icon-1024.svg --out "$ICONSET/icon_512x512@2x.png" >/dev/null
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    if [ "$SIZE" -le 256 ]; then
        DOUBLE=$((SIZE * 2))
        sips -z "$DOUBLE" "$DOUBLE" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "아이콘 생성: Resources/AppIcon.icns"
