#!/bin/bash
# Builds and signs HayFutbol.app into build/.
#
# A hand-assembled bundle rather than an .xcodeproj: a menu bar app is one
# executable, an Info.plist and an icon, which a script says more plainly than
# a pbxproj does.
#
#   ./build.sh              build and sign into build/
#   ./build.sh install      also copy to /Applications and launch it
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HayFutbol"
BUNDLE="build/${APP_NAME}.app"
DEPLOY_TARGET="macos13.0"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning |
    awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "no Developer ID Application identity found; set CODESIGN_IDENTITY" >&2
    exit 1
fi

rm -rf build
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

echo "==> compiling"
# Universal, so the DMG works on whichever Mac it gets passed along to.
for ARCH in arm64 x86_64; do
    swiftc Sources/*.swift \
        -target "${ARCH}-apple-${DEPLOY_TARGET}" \
        -swift-version 6 \
        -framework AppKit -framework ServiceManagement -framework UserNotifications \
        -O -o "build/${APP_NAME}-${ARCH}"
done
lipo -create build/${APP_NAME}-arm64 build/${APP_NAME}-x86_64 \
    -output "${BUNDLE}/Contents/MacOS/${APP_NAME}"
rm build/${APP_NAME}-arm64 build/${APP_NAME}-x86_64

cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> signing as ${IDENTITY}"
codesign --force --timestamp=none --options runtime \
    --sign "${IDENTITY}" "${BUNDLE}"
codesign --verify --strict --verbose=2 "${BUNDLE}"

echo "==> built ${BUNDLE}"

if [ "${1:-}" = "install" ]; then
    echo "==> installing to /Applications"
    pkill -x "${APP_NAME}" || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${BUNDLE}" /Applications/
    open "/Applications/${APP_NAME}.app"
fi
