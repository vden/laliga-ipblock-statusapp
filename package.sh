#!/bin/bash
# Builds a release DMG: signed, notarized, stapled.
#
# Separate from build.sh, which is the fast loop with no network; notarization
# is a round trip to Apple that takes minutes.
#
#   ./package.sh 1.0.0
#
# Credentials come from a notarytool keychain profile. The default is the one
# already set up for team 6W25N2CW6H; to make another:
#
#   xcrun notarytool store-credentials <name> \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# and pass it as NOTARY_PROFILE=<name>.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: $0 <version>   e.g. $0 1.0.0" >&2
    exit 1
fi

APP_NAME="HayFutbol"
BUNDLE="build/${APP_NAME}.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-coredeck-notary}"
DMG="build/${APP_NAME}-${VERSION}.dmg"
STAGING="build/dmg"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning |
    awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "no Developer ID Application identity found; set CODESIGN_IDENTITY" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
echo "==> building ${APP_NAME} ${VERSION}"

./build.sh >/dev/null
# Stamped before signing, since editing the plist afterwards breaks the seal.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
    -c "Set :CFBundleVersion ${VERSION}" "${BUNDLE}/Contents/Info.plist"

# build.sh signs without a timestamp to stay offline; notarization needs one.
codesign --force --timestamp --options runtime --sign "${IDENTITY}" "${BUNDLE}"
codesign --verify --strict "${BUNDLE}"

# ---------------------------------------------------------------------------
echo "==> notarizing the app (a few minutes)"

# notarytool takes a zip or a disk image, never a bare bundle. ditto rather than
# zip, which can mangle the symlinks and extended attributes a signature covers.
ZIP="build/${APP_NAME}-${VERSION}.zip"
/usr/bin/ditto -c -k --keepParent "${BUNDLE}" "${ZIP}"
xcrun notarytool submit "${ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
rm -f "${ZIP}"

# Stapled so the first launch validates without a network round trip.
xcrun stapler staple "${BUNDLE}"
xcrun stapler validate "${BUNDLE}"

# ---------------------------------------------------------------------------
echo "==> building ${DMG}"

rm -rf "${STAGING}" "${DMG}"
mkdir -p "${STAGING}"
cp -R "${BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" \
    -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGING}"

# Gatekeeper judges what the user double-clicked, so the image is signed and
# notarized in its own right.
codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG}"

echo
echo "==> ${DMG}"
spctl --assess --type open --context context:primary-signature -v "${DMG}" 2>&1 | sed 's/^/    /'
shasum -a 256 "${DMG}" | sed 's/^/    /'
