#!/usr/bin/env bash
#
# Build Carafe and launch it.
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Xcode is often not the selected developer directory on machines that also have
# the Command Line Tools installed. Point at it explicitly rather than requiring
# `sudo xcode-select -s`, which this script has no business demanding.
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

CONFIGURATION="${1:-Debug}"

if [ ! -d Carafe.xcodeproj ]; then
	echo "==> Carafe.xcodeproj missing, generating"
	./Scripts/bootstrap.sh
fi

echo "==> Building ($CONFIGURATION)"
xcodebuild -scheme Carafe -configuration "$CONFIGURATION" \
	-destination 'platform=macOS' build -quiet

APP="$(xcodebuild -scheme Carafe -configuration "$CONFIGURATION" \
	-destination 'platform=macOS' -showBuildSettings 2>/dev/null |
	awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Carafe.app"

echo "==> Relaunching $APP"
killall Carafe 2>/dev/null || true
open "$APP"

echo
echo "Carafe is running in the menu bar. It has no Dock icon by design."
echo "Quit it from the popover's Settings page, or: killall Carafe"
