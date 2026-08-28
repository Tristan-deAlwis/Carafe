#!/usr/bin/env bash
#
# Bootstrap the Carafe development environment.
#
# project.yml is the source of truth; Carafe.xcodeproj is generated and
# gitignored. Run this after cloning, and any time project.yml changes.
#
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
	echo "==> xcodegen not found, installing via Homebrew"
	if ! command -v brew >/dev/null 2>&1; then
		echo "error: Homebrew is required. See https://brew.sh" >&2
		exit 1
	fi
	brew install xcodegen
fi

echo "==> Generating Carafe.xcodeproj from project.yml"
xcodegen generate

echo
echo "Done. Next:"
echo "  ./Scripts/build.sh          # build and launch Carafe.app"
echo "  open Carafe.xcodeproj       # or work in Xcode"
