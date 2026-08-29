#!/usr/bin/env bash
#
# Build a distributable Carafe.app: universal, signed, notarized, zipped.
#
# Signing and notarization are opt-in through the environment, and the script
# degrades cleanly when they are absent:
#
#   DEVELOPER_ID_APPLICATION  "Developer ID Application: Name (TEAMID)"
#                             Unset -> ad-hoc signature, and a loud warning.
#   NOTARY_PROFILE            notarytool keychain profile name.
#                             Unset -> notarization skipped.
#
# Set both up once with:
#   xcrun notarytool store-credentials "carafe" \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
set -euo pipefail

cd "$(dirname "$0")/.."

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

BUILD_DIR="build"
DIST_DIR="dist"
ARCHIVE="$BUILD_DIR/Carafe.xcarchive"

rm -rf "$ARCHIVE" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

./Scripts/bootstrap.sh >/dev/null

# ---------------------------------------------------------------------------
# Archive. `generic/platform=macOS` with ONLY_ACTIVE_ARCH=NO (set in project.yml
# for Release) produces the universal arm64 + x86_64 binary distribution needs.
# ---------------------------------------------------------------------------
echo "==> Archiving (universal)"
xcodebuild archive \
	-scheme Carafe \
	-configuration Release \
	-destination 'generic/platform=macOS' \
	-archivePath "$ARCHIVE" \
	CODE_SIGN_IDENTITY="-" \
	-quiet

APP="$DIST_DIR/Carafe.app"
cp -R "$ARCHIVE/Products/Applications/Carafe.app" "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
echo "==> Carafe $VERSION"

echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/Carafe")"

# ---------------------------------------------------------------------------
# Sign.
# ---------------------------------------------------------------------------
SIGNED_PROPERLY=false
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
	echo "==> Signing with Developer ID"
	# Hardened Runtime is required for notarization.
	codesign --force --options runtime --timestamp \
		--entitlements Sources/Carafe.entitlements \
		--sign "$DEVELOPER_ID_APPLICATION" \
		"$APP"
	SIGNED_PROPERLY=true
else
	echo "==> WARNING: DEVELOPER_ID_APPLICATION unset — ad-hoc signing."
	echo "    Gatekeeper will block this build on other machines, and macOS will"
	echo "    refuse to deliver notifications (Carafe falls back to marking its"
	echo "    menu bar icon). Fine for local testing; not for release."
	codesign --force --sign - "$APP"
fi

codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# ---------------------------------------------------------------------------
# Package.
# ---------------------------------------------------------------------------
ZIP="$DIST_DIR/Carafe-$VERSION.zip"
echo "==> Packaging $ZIP"
# ditto preserves the bundle's symlinks and extended attributes; `zip` does not.
ditto -c -k --keepParent "$APP" "$ZIP"

# ---------------------------------------------------------------------------
# Notarize. Requires a real signature, so it is skipped alongside signing.
# ---------------------------------------------------------------------------
if [ "$SIGNED_PROPERLY" = true ] && [ -n "${NOTARY_PROFILE:-}" ]; then
	echo "==> Submitting for notarization (this takes a few minutes)"
	xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

	echo "==> Stapling"
	xcrun stapler staple "$APP"
	# Re-zip so the distributed archive contains the stapled ticket, letting
	# Gatekeeper validate offline.
	rm "$ZIP"
	ditto -c -k --keepParent "$APP" "$ZIP"
	xcrun stapler validate "$APP"
else
	echo "==> Skipping notarization (needs DEVELOPER_ID_APPLICATION and NOTARY_PROFILE)"
fi

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo
echo "-----------------------------------------------------------"
echo " Carafe $VERSION"
echo " Artifact : $ZIP"
echo " SHA-256  : $SHA"
echo " Notarized: $([ "$SIGNED_PROPERLY" = true ] && [ -n "${NOTARY_PROFILE:-}" ] && echo yes || echo no)"
echo "-----------------------------------------------------------"
echo
echo "Attach $ZIP to the GitHub release and publish the SHA-256 alongside it."
