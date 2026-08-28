#!/usr/bin/env bash
#
# Regenerate Sources/Assets.xcassets/AppIcon.appiconset from AppIconView.
#
# The PNGs are rendered by IconGeneratorTests, because ImageRenderer needs a host
# app process. Run this after changing CarafeShape or AppIconView, then commit the
# regenerated PNGs.
#
set -euo pipefail

cd "$(dirname "$0")/.."

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

ICON_DIR="$PWD/Sources/Assets.xcassets/AppIcon.appiconset"

echo "==> Rendering icon set into $ICON_DIR"
TEST_RUNNER_CARAFE_ICON_DIR="$ICON_DIR" \
	xcodebuild -scheme Carafe -destination 'platform=macOS' \
	-only-testing:CarafeTests/IconGeneratorTests test \
	-quiet

echo "==> Generated:"
ls -1 "$ICON_DIR"/*.png
