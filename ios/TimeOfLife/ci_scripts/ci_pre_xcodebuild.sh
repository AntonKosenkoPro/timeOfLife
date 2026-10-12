#!/bin/sh
# Xcode Cloud pre-xcodebuild script: SwiftLint gate (mirrors ios.yml).
#
# Runs before every Cloud xcodebuild action — PR-check builds and tag
# archives alike. Tags build from lint-green main, so the gate is a no-op
# there; PR builds fail fast here instead of after an expensive compile.
# swiftlint is intentionally NOT part of ci_post_clone.sh: lint belongs to
# the build phase it gates, and a lint failure must read as a build
# failure in Cloud's action reporting.
#
# Pin (move-ios-checks-to-xcode-cloud): asserted fail-closed like xcodegen
# in ci_post_clone.sh. Bump SWIFTLINT_PIN (and docs/ci.md) with the local
# toolchain; never relax --strict to fix a version-skew failure — pin.
set -e

cd "$(dirname "$0")/.."

SWIFTLINT_PIN="0.65.0"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not found — installing via Homebrew..."
  brew install swiftlint
fi

echo "swiftlint $(swiftlint version)"
case "$(swiftlint version)" in
  *"$SWIFTLINT_PIN"*) ;;
  *)
    echo "error: swiftlint version drift — expected $SWIFTLINT_PIN. Bump SWIFTLINT_PIN (and docs/ci.md) if intentional."
    exit 1
    ;;
esac

swiftlint lint --strict
