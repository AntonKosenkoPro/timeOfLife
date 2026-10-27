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
# replaces tag discovery when set, even when set to empty (which forces
# the no-tag path). Tags are discovered with `git tag --points-at HEAD`
# (after a retried tag fetch that fails closed): the same-commit promotion
# (`internal/vX` + `release/vX`, the normal dogfood→public path) is
# allowed and disambiguated by $CI_WORKFLOW (pinned names, docs/ci.md);
# two tags in one namespace, or a pair with different marketing versions,
# abort. Non-iOS tags sharing HEAD are ignored. A tag-triggered archive
# must never ship the dev dummy.
# The build number is channel-banded (N*2+chanbit)*STRIDE plus Xcode
# Cloud's per-workflow $CI_BUILD_NUMBER: internal and public are separate
# workflows with independent counters, so raw run numbers can order
# backwards across channels for one marketing line (App Store Connect
# rejects re-uploads at or below the previous build). Tags are cut in
# (N, channel) time order (dogfood before public), which keeps the stamped
# number increasing while RUN stays below STRIDE.
# Local simulations must export CI_BUILD_NUMBER explicitly.
if [ "${TAG_OVERRIDE+x}" = "x" ]; then
  TAG="$TAG_OVERRIDE"
else
  # The fetch is retried-then-fatal on purpose: without tag refs a
  # tag-triggered archive cannot be told apart from a PR build, and guessing
  # wrong ships the dev dummy (fail-closed beats a green-but-wrong archive).
  # A transient hiccup retries so unrelated PR CI isn't blocked by a git
  # blip; a genuinely unreachable remote still aborts.
  FETCH_OK=0
  for _ in 1 2 3; do
    if git fetch --tags origin >/dev/null 2>&1; then
      FETCH_OK=1
      break
    fi
    sleep 5
  done
  if [ "$FETCH_OK" != "1" ]; then
    echo "error: tag fetch failed 3x and no \$TAG_OVERRIDE is set — refusing to guess (a tag-triggered archive must never ship the dev dummy). Archiving nothing."
    exit 1
  fi
  TAGS="$(git tag --points-at HEAD 2>/dev/null || echo __GIT_FAILED__)"
  if [ "$TAGS" = "__GIT_FAILED__" ]; then
    echo "error: cannot enumerate tags at HEAD and no \$TAG_OVERRIDE is set — refusing to guess (a tag-triggered archive must never ship the dev dummy). Archiving nothing."
    exit 1
  fi
  # At most one iOS release namespace may tag a commit — except the
  # same-commit promotion (internal/vX + release/vX, the normal
  # dogfood→public path), which CI_WORKFLOW disambiguates. Workflow names
  # are pinned (docs/ci.md runbook): "iOS Internal Release" cuts internal,
  # "iOS Public Release" cuts public. Non-iOS tags sharing HEAD
  # (backend/*, checkpoint tags) are ignored, not errors.
  IOS_TAGS="$(printf '%s\n' "$TAGS" | grep -E '^(internal|release)/' || true)"
  IOS_TAG_COUNT="$(printf '%s\n' "$TAGS" | grep -cE '^(internal|release)/' || true)"
  if [ "$IOS_TAG_COUNT" -gt 1 ]; then
    case "${CI_WORKFLOW:-}" in
      "iOS Internal Release") WANT_NS="internal" ;;
      "iOS Public Release") WANT_NS="release" ;;
      *)
        echo "error: multiple iOS release tags at HEAD and CI_WORKFLOW='${CI_WORKFLOW:-}' cannot disambiguate:"
        printf '%s\n' "$IOS_TAGS"
        echo "Archiving nothing."
        exit 1
        ;;
    esac
    NS_TAGS="$(printf '%s\n' "$IOS_TAGS" | grep -E "^${WANT_NS}/" || true)"
    # A promotion pair must share one marketing version: internal/v0.2.7 +
    # release/v0.3.0 at one commit is a typo (or a half-tagged fix), and
    # stamping the workflow's pick would silently ship the wrong marketing
    # while skipping the dogfood-before-public guarantee. The sibling is
    # printed here, never silently dropped.
    PAIR_VERSIONS="$(printf '%s\n' "$IOS_TAGS" | sed -E 's|^[^/]*/v||' | cut -d. -f1-3 | sort -u | tr '\n' ' ')"
    if [ "$(printf '%s\n' "$IOS_TAGS" | sed -E 's|^[^/]*/v||' | cut -d. -f1-3 | sort -u | grep -c . || true)" != "1" ]; then
      echo "error: iOS tags at HEAD span multiple marketing versions [$PAIR_VERSIONS]— a promotion pair must share one vM.m.p. Nothing is stamped. Archiving nothing."
      exit 1
    fi
    # Re-uploads share the commit (the original tag never moves), so one
    # namespace routinely holds several tags here (internal/v0.2.7,
    # internal/v0.2.7.2, ...). Stamp the highest re-upload sequence —
    # deterministically the newest intent; equal sequences are ambiguous.
    TAG=""
    BEST_N=-1
    for CANDIDATE_TAG in $NS_TAGS; do
      CANDIDATE_N="$(printf '%s' "${CANDIDATE_TAG#*/}" | cut -d. -f4)"
      if [ -z "$CANDIDATE_N" ]; then
        CANDIDATE_N=1
      fi
      CANDIDATE_N="$(printf '%s' "$CANDIDATE_N" | sed 's/^0*//')"
      if [ -z "$CANDIDATE_N" ]; then
        CANDIDATE_N=0
      fi
      case "$CANDIDATE_N" in
        *[!0-9]*) echo "error: tag '$CANDIDATE_TAG' carries a non-numeric sequence — refusing to order it. Archiving nothing."; exit 1 ;;
      esac
      # Length guard (same class as SEQ/BUILD_RUN below): an over-long value
      # makes the integer comparisons error out and skip silently. Five
      # digits always suffice (MAX_SEQ is 10736).
      if [ "${#CANDIDATE_N}" -gt 5 ]; then
        echo "error: tag '$CANDIDATE_TAG' carries re-upload sequence $CANDIDATE_N — out of range. Archiving nothing."
        exit 1
      fi
      if [ "$CANDIDATE_N" -gt "$BEST_N" ]; then
        BEST_N="$CANDIDATE_N"
        TAG="$CANDIDATE_TAG"
      elif [ "$CANDIDATE_N" -eq "$BEST_N" ]; then
        echo "error: duplicate re-upload sequence $CANDIDATE_N among $WANT_NS tags at HEAD — ambiguous which to stamp. Archiving nothing."
        exit 1
      fi
    done
    if [ -z "$TAG" ]; then
      echo "error: workflow '$CI_WORKFLOW' found no $WANT_NS tag at HEAD; found:"
      printf '%s\n' "$IOS_TAGS"
      echo "Archiving nothing."
      exit 1
    fi
  else
    TAG="$IOS_TAGS"
  fi
fi

if [ -z "$TAG" ]; then
  echo "No release tag at HEAD — leaving project.yml versions untouched."
  exit 0
fi

# The single-tag path still verifies the trigger: a lone tag from the other
# namespace (e.g. only release/v0.3.0 while "iOS Internal Release" runs)
# would otherwise stamp the wrong channel silently.
if [ -n "${CI_WORKFLOW:-}" ]; then
  case "$CI_WORKFLOW" in
    "iOS Internal Release") EXPECT_NS="internal" ;;
    "iOS Public Release") EXPECT_NS="release" ;;
    *) EXPECT_NS="" ;;
  esac
  if [ -n "$EXPECT_NS" ]; then
    case "$TAG" in
      "${EXPECT_NS}/"*) ;;
      *)
        echo "error: tag '$TAG' is not in the $EXPECT_NS namespace, but workflow '$CI_WORKFLOW' triggered this build — refusing to stamp the wrong channel. Archiving nothing."
        exit 1
        ;;
    esac
  fi
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
SEQ="$(printf '%s' "${VERSION#v}" | cut -d. -f4)"
if [ -z "$SEQ" ]; then
  SEQ=1
fi
# Sequence is part of the build number, so it must be a real positive
# integer in range: `0` (or leading zeros, which $(( )) would read as
# octal) collapses/mis-orders the stamped build, and App Store Connect
# accepts CFBundleVersion only up to 2^31-1.
SEQ="$(printf '%s' "$SEQ" | sed 's/^0*//')"
if [ -z "$SEQ" ]; then
  echo "error: tag '$TAG' carries re-upload sequence 0 — the banded ordering ((N*2+chanbit)*STRIDE+RUN) assumes N >= 1. Archiving nothing."
  exit 1
fi

STRIDE=100000
BUILD_RUN="${CI_BUILD_NUMBER:-}"
case "$BUILD_RUN" in
  ''|*[!0-9]*)
    echo "error: tag '$TAG' is present but \$CI_BUILD_NUMBER is missing or not numeric — refusing to stamp a guessable build number. Archiving nothing."
    exit 1
    ;;
esac
# Length guard before any arithmetic: an over-long value makes `[ -ge ]`
# exit status 2 (treated as false inside `if`, skipping the check) and
# `$(( ))` wrap — failing open with a bogus build number. Five digits
# always suffice (STRIDE is six).
if [ "${#BUILD_RUN}" -gt 5 ] || [ "$BUILD_RUN" -ge "$STRIDE" ]; then
  echo "error: \$CI_BUILD_NUMBER=$BUILD_RUN is not a usable run number (must be 1..99999) — refusing to stamp it. Archiving nothing."
  exit 1
fi
# Strip leading zeros ($(( )) would read them as octal), then reject 0:
# a CFBundleVersion of 0 is not uploadable.
BUILD_RUN="$(printf '%s' "$BUILD_RUN" | sed 's/^0*//')"
if [ -z "$BUILD_RUN" ]; then
  echo "error: tag '$TAG' resolved to build number 0, which App Store Connect rejects — refusing to stamp it. Archiving nothing."
  exit 1
fi
# Channel-banded build number: internal and public are separate Cloud
# workflows with independent run counters, so raw run numbers can order
# backwards across channels for one marketing line (App Store Connect
# rejects a re-upload with a build number at or below the previous one).
# Each sequence number N owns a band of 2*STRIDE; public takes the upper
# half. Tags are cut in (N, channel) time order (dogfood before public),
# so (N*2+chanbit)*STRIDE+RUN increases along any legal tag sequence
# while RUN stays below STRIDE. Reversing channels at one N (public
# before internal) violates the runbook and is rejected by ASC, not here.
if [ "$CHANNEL" = "public" ]; then
  CHANBIT=1
else
  CHANBIT=0
fi
# App Store Connect accepts CFBundleVersion up to 2^31-1: keep the whole
# stamped number inside that range at the largest accepted sequence.
MAX_SEQ="$(( (2147483647 - 2 * STRIDE + 1) / (2 * STRIDE) ))"
# Length guard first: beyond 5 digits the value may exceed the shell's
# integer range, in which case `[ -gt ]` errors (status 2, silently skipped
# in an `if` condition) and $(( )) wraps — failing open. MAX_SEQ is 10736.
if [ "${#SEQ}" -gt 5 ] || [ "$SEQ" -gt "$MAX_SEQ" ]; then
  echo "error: tag '$TAG' has re-upload sequence $SEQ — the banded build would exceed App Store Connect's 2^31-1 limit (max sequence $MAX_SEQ). Archiving nothing."
  exit 1
fi
BUILD="$(( (SEQ * 2 + CHANBIT) * STRIDE + BUILD_RUN ))"

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
