#!/bin/sh
# Xcode Cloud post-clone script.
#
# The .xcodeproj is gitignored (XcodeGen-managed: edit project.yml, then
# `xcodegen generate`), so generate it here before Xcode Cloud builds.
# SwiftPM dependencies (GRDB) resolve automatically during the build.
set -e

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found — installing via Homebrew..."
  brew install xcodegen
fi

echo "xcodegen $(xcodegen --version)"
xcodegen generate
