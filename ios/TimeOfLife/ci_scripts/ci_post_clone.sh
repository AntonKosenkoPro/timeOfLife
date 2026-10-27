#!/bin/sh
# Xcode Cloud post-clone script (PR checks + tag archives).
#
# The .xcodeproj is gitignored (XcodeGen-managed: edit project.yml, then
# `xcodegen generate`), so generate it here before Xcode Cloud builds.
# SwiftPM dependencies (GRDB) resolve automatically during the build.
#
# Toolchain pins (move-ios-checks-to-xcode-cloud): versions are asserted
# fail-closed after install — a drifted Homebrew bottle fails the build
# loudly instead of checking with the wrong toolchain. Bump the pins here
# (and in docs/ci.md) when the local toolchain moves.
set -e

cd "$(dirname "$0")/.."

XCODEGEN_PIN="2.46.0"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found — installing via Homebrew..."
  brew install xcodegen
fi

echo "xcodegen $(xcodegen --version)"
case "$(xcodegen --version)" in
  *"$XCODEGEN_PIN"*) ;;
  *)
    echo "error: xcodegen version drift — expected $XCODEGEN_PIN. Bump XCODEGEN_PIN (and docs/ci.md) if intentional."
    exit 1
    ;;
esac

generate_project() {
  xcodegen generate

  # The generate must yield a usable project (postGenCommand
  # normalize-system-capabilities.py runs as part of it).
  if [ ! -d "TimeOfLife.xcodeproj" ]; then
    echo "error: xcodegen generate produced no TimeOfLife.xcodeproj."
    exit 1
  fi
}

generate_project

# --- Manual tag releases (manual-tag-releases change) ---
#
# Tag-triggered Cloud workflows stamp versions at build time: the owner's
# signed `internal/vM.m.p[.n]` / `release/vM.m.p[.n]` tag at HEAD carries the
# marketing version (first three components; the optional fourth is the
# re-upload sequence, NOT part of marketing) and the channel. PR builds and
# local dev have no such tag and keep the checked-in dev dummy.
#
# Versions flow pre-generate: this script edits project.yml, re-runs
# `xcodegen generate` so the generated Info.plists pick the stamped values
# up, then asserts unanimity across all targets (failing the archive on
# skew). $TAG_OVERRIDE (local simulation only — Cloud never sets it)
# replaces `git describe` when set, even when set to empty (which forces
# the no-tag path). The build number is Xcode Cloud's per-workflow
# $CI_BUILD_NUMBER (monotonic per workflow, so App Store Connect build
# numbers increase); local simulations must export it explicitly.
if [ "${TAG_OVERRIDE+x}" = "x" ]; then
  TAG="$TAG_OVERRIDE"
else
  TAG="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
fi

if [ -z "$TAG" ]; then
  echo "No release tag at HEAD — leaving project.yml versions untouched."
  exit 0
fi

case "$TAG" in
  internal/*|release/*) ;;
  *)
    echo "Tag '$TAG' is not an iOS release tag — leaving project.yml versions untouched."
    exit 0
    ;;
esac

NAMESPACE="${TAG%%/*}"
VERSION="${TAG#*/}"
if [ "$NAMESPACE" = "internal" ]; then
  CHANNEL="internal"
else
  CHANNEL="public"
fi

if ! printf '%s' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  echo "error: tag '$TAG' is not <namespace>/vM.m.p[.n] with numeric semver (e.g. internal/v0.2.7, release/v0.3.0.2). Never move a pushed tag — cut a new one with a fixed name. Archiving nothing."
  exit 1
fi

MARKETING="$(printf '%s' "${VERSION#v}" | cut -d. -f1-3)"

BUILD="${CI_BUILD_NUMBER:-}"
case "$BUILD" in
  ''|*[!0-9]*)
    echo "error: tag '$TAG' is present but \$CI_BUILD_NUMBER is missing or not a positive integer — refusing to stamp a guessable build number. Archiving nothing."
    exit 1
    ;;
esac

echo "Release tag '$TAG': stamping MARKETING_VERSION=$MARKETING BUILD=$BUILD CHANNEL=$CHANNEL."

MARKETING="$MARKETING" BUILD="$BUILD" CHANNEL="$CHANNEL" python3 - <<'EOF'
import os, re, sys

path = "project.yml"
with open(path) as f:
    src = f.read()

wants = [
    ("CFBundleShortVersionString", os.environ["MARKETING"]),
    ("CFBundleVersion", os.environ["BUILD"]),
    ("CURRENT_PROJECT_VERSION", os.environ["BUILD"]),
    ("MARKETING_VERSION", os.environ["MARKETING"]),
    ("RELEASE_CHANNEL", os.environ["CHANNEL"]),
]
# Expected occurrences in project.yml: app + appex generated plists,
# app + appex generated plists, app + framework build settings,
# framework build settings, app generated plist.
expected = {
    "CFBundleShortVersionString": 2,
    "CFBundleVersion": 2,
    "CURRENT_PROJECT_VERSION": 2,
    "MARKETING_VERSION": 1,
    "RELEASE_CHANNEL": 1,
}

for key, value in wants:
    pattern = re.compile(r'(?m)^(\s*%s: )"[^"]*"(.*)$' % re.escape(key))
    src, n = pattern.subn(r'\1"%s"\2' % value, src)
    if n != expected[key]:
        print("error: expected %d %s entries in project.yml, found %d — a target moved its versions out of XcodeGen management." % (expected[key], key, n))
        sys.exit(1)

with open(path, "w") as f:
    f.write(src)
print("project.yml stamped.")
EOF

generate_project

MARKETING="$MARKETING" BUILD="$BUILD" CHANNEL="$CHANNEL" python3 - <<'EOF'
import os, plistlib, re, sys

marketing, build, channel = os.environ["MARKETING"], os.environ["BUILD"], os.environ["CHANNEL"]
failures = []

def check_plist(path, wants_channel):
    try:
        with open(path, "rb") as f:
            info = plistlib.load(f)
    except Exception as exc:
        failures.append("%s: unreadable (%s)" % (path, exc))
        return
    if info.get("CFBundleShortVersionString") != marketing:
        failures.append("%s: CFBundleShortVersionString=%r, want %r" % (path, info.get("CFBundleShortVersionString"), marketing))
    if info.get("CFBundleVersion") != build:
        failures.append("%s: CFBundleVersion=%r, want %r" % (path, info.get("CFBundleVersion"), build))
    if wants_channel and info.get("RELEASE_CHANNEL") != channel:
        failures.append("%s: RELEASE_CHANNEL=%r, want %r" % (path, info.get("RELEASE_CHANNEL"), channel))

# The framework has no on-disk plist (GENERATE_INFOPLIST_FILE is filled at
# build time) — its MARKETING_VERSION/CURRENT_PROJECT_VERSION are asserted
# in project.yml below.
check_plist("TimeOfLife/Configuration/Info.plist", True)
check_plist("LifioLiveActivities/Info.plist", False)

with open("project.yml") as f:
    src = f.read()
for key, value in (("MARKETING_VERSION", marketing), ("CURRENT_PROJECT_VERSION", build)):
    found = re.findall(r'(?m)^\s*%s: "([^"]*)"' % re.escape(key), src)
    if not found or any(v != value for v in found):
        failures.append("project.yml: %s=%r, want every entry %r" % (key, found, value))

if failures:
    print("error: version unanimity check failed:")
    for failure in failures:
        print("  - " + failure)
    sys.exit(1)
print("Version unanimity OK: marketing=%s build=%s channel=%s." % (marketing, build, channel))
EOF
