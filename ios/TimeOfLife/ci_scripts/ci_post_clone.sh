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
# Sequence numbers: the bare tag (no fourth component) is the base, N=0;
# explicit re-uploads start at .1. Prints nothing for a present-but-invalid
# sequence (all-zeros, non-numeric) so callers fail closed on it.
# Namespace a Cloud workflow cuts, from the pinned CI_WORKFLOW name
# (docs/ci.md runbook). Single definition shared by both disambiguation
# paths below so a rename can never update one and silently fail open
# the other. Prints the namespace; fails with no output otherwise —
# callers print their own context and exit.
wanted_ns() {
  case "${CI_WORKFLOW:-}" in
    "iOS Internal Release") printf 'internal' ;;
    "iOS Public Release") printf 'release' ;;
    *) return 1 ;;
  esac
}
tag_seq() {
  # Prints the numeric re-upload sequence: absent means the base (0).
  # Return codes distinguish the cases callers must message differently:
  # 0 with a number = usable (absent prints "0"); 2 with no output =
  # invalid input (non-numeric, or present-but-all-zeros) — callers fail
  # closed naming the tag, never "sequence 0" for a typo.
  _s="$(printf '%s' "$1" | cut -d. -f4)"
  if [ -z "$_s" ]; then
    printf '0'
    return 0
  fi
  _s="$(printf '%s' "$_s" | sed 's/^0*//')"
  case "$_s" in
    ''|*[!0-9]*) return 2 ;;
  esac
  printf '%s' "$_s"
}
# Banding constants, defined ONCE at the top so every bound below derives
# from them — never duplicate the literal (a second copy edited alone would
# silently diverge the bounds). STRIDE is the per-(sequence,channel) band
# width; MAX_SEQ the largest sequence whose stamped build stays within App
# Store Connect's CFBundleVersion limit of 2^31-1 (10736). All length
# guards below use ${#MAX_SEQ} rather than a hardcoded digit count.
STRIDE=100000
MAX_SEQ="$(( (2147483647 - 2 * STRIDE + 1) / (2 * STRIDE) ))"
if [ "${TAG_OVERRIDE+x}" = "x" ]; then
  # Local simulation only: Xcode Cloud never sets TAG_OVERRIDE, and an
  # override skips signature verification below — a Cloud build carrying
  # one would stamp an unverified version, so fail closed instead.
  # (CI_XCODE_CLOUD: Apple environment-variable reference, always present
  # on Cloud; presence-checked (`${var+x}`) so a set-but-empty value cannot
  # bypass the guard.)
  if [ "${CI_XCODE_CLOUD+x}" = "x" ]; then
    echo "error: \$TAG_OVERRIDE is set in an Xcode Cloud build — local simulation only, refusing to stamp an unverified tag. Archiving nothing."
    exit 1
  fi
  TAG="$TAG_OVERRIDE"
else
  # The fetch is retried-then-fatal on purpose: without tag refs a
  # tag-triggered archive cannot be told apart from a PR build, and guessing
  # wrong ships the dev dummy (fail-closed beats a green-but-wrong archive).
  # A transient hiccup retries so unrelated PR CI isn't blocked by a git
  # blip; a genuinely unreachable remote still aborts.
  FETCH_OK=0
  for _ in 1 2 3; do
    # Explicit full refspec: Cloud clones are shallow with an unknown
    # clone-time refspec, so even `origin main` may not refresh the tracking
    # ref the signature gate reads its anchor from. Never forced: tags are
    # never force-updated.
    if git fetch --tags origin refs/heads/main:refs/remotes/origin/main >/dev/null 2>&1; then
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
    if ! WANT_NS="$(wanted_ns)"; then
      echo "error: multiple iOS release tags at HEAD and CI_WORKFLOW='${CI_WORKFLOW:-}' cannot disambiguate:"
      printf '%s\n' "$IOS_TAGS"
      echo "Archiving nothing."
      exit 1
    fi
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
      if ! CANDIDATE_N="$(tag_seq "${CANDIDATE_TAG#*/}")"; then
        echo "error: tag '$CANDIDATE_TAG' has an invalid or zero re-upload sequence — explicit re-uploads need .1+ numeric (the bare tag is the base; check for typos like .abc or .0). Archiving nothing."
        exit 1
      fi
      # Length guard (same class as SEQ/BUILD_RUN below): an over-long value
      # makes the integer comparisons error out and skip silently. Cap
      # derives from MAX_SEQ so a future STRIDE change cannot strand it.
      if [ "${#CANDIDATE_N}" -gt "${#MAX_SEQ}" ]; then
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
      echo "error: workflow '$CI_WORKFLOW' found no $WANT_NS tag at HEAD (candidates considered: [$(printf '%s' "$NS_TAGS" | tr '\n' ' ')]; all iOS tags: [$(printf '%s' "$IOS_TAGS" | tr '\n' ' ')]). Archiving nothing."
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
# would otherwise stamp the wrong channel silently. An unrecognized
# CI_WORKFLOW with a tag present means the pinned workflow names drifted
# (docs/ci.md) and the channel cannot be verified — fail closed, never skip.
if [ -n "${CI_WORKFLOW:-}" ]; then
  if ! EXPECT_NS="$(wanted_ns)"; then
    echo "error: CI_WORKFLOW='$CI_WORKFLOW' is not a pinned release workflow name (docs/ci.md) — cannot verify the channel for tag '$TAG'. Archiving nothing."
    exit 1
  fi
  case "$TAG" in
    "${EXPECT_NS}/"*) ;;
    *)
      echo "error: tag '$TAG' is not in the $EXPECT_NS namespace, but workflow '$CI_WORKFLOW' triggered this build — refusing to stamp the wrong channel. Archiving nothing."
      exit 1
      ;;
  esac
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

# Signature gate (spec: release tags are `-s` signed). GitHub has no native
# tag-signature rule, so this is the enforcement on the iOS path: unsigned,
# lightweight, wrong-key, or non-OpenPGP tags fail the archive before
# anything is stamped. Skipped only for TAG_OVERRIDE (local simulation /
# harness — fails closed on Cloud instead). STAMP_SIGNING_KEY selects the
# harness throwaway key off-Cloud only (fails closed on Cloud — the repo key
# is the sole Cloud anchor). Otherwise the anchor is read from
# freshly-fetched origin/main — never the tag checkout under verification
# (parity with backend-release.yml; rotated-out keys fail closed).
# Verification runs in an ephemeral GNUPGHOME (saved/restored, trapped;
# INT/TERM exit 130 so a signal never resumes into stamping). The guarantee
# is backend lockdown, not the armor pre-filter: verify-tag routes by
# signature blob, so inherited config (e.g. gpg.ssh allowedSigners) could
# otherwise verify an SSH-signed tag — hence ssh/x509 programs are pinned to
# /usr/bin/false and OpenPGP to gpg. gpg/verify stderr prints on failure.
if [ "${TAG_OVERRIDE+x}" != "x" ]; then
  if [ "${CI_XCODE_CLOUD+x}" = "x" ] && [ "${STAMP_SIGNING_KEY+x}" = "x" ]; then
    echo "error: \$STAMP_SIGNING_KEY is set in an Xcode Cloud build — the repo release key is the sole Cloud trust anchor. Archiving nothing."
    exit 1
  fi
  if [ -n "${STAMP_SIGNING_KEY:-}" ]; then
    if [ ! -f "$STAMP_SIGNING_KEY" ]; then
      echo "error: release signing key not found at '$STAMP_SIGNING_KEY' — cannot verify tag '$TAG'. Archiving nothing."
      exit 1
    fi
    if ! KEY_ARMOR="$(cat "$STAMP_SIGNING_KEY" 2>/dev/null)" || [ -z "$KEY_ARMOR" ]; then
      echo "error: cannot read release signing key from '$STAMP_SIGNING_KEY' — cannot verify tag '$TAG'. Archiving nothing."
      exit 1
    fi
  else
    # A missing ref or file fails closed — never fall back to the checkout.
    if ! KEY_ARMOR="$(git show "origin/main:.github/release-signing-key.pub" 2>/dev/null)" || [ -z "$KEY_ARMOR" ]; then
      echo "error: cannot read the release signing key from origin/main — cannot verify tag '$TAG'. Archiving nothing."
      exit 1
    fi
  fi
  # Last-armor pre-filter (diagnostic only, NOT the security guarantee): the
  # tag object's LAST '^-----BEGIN ' line must open the PGP block, so plain
  # unsigned / lightweight / SSH-signed tags are refused here with a precise
  # message before any backend is invoked. It must not be relied on: no armor
  # heuristic can prove how every git version routes a hostile object.
  if [ "$(git cat-file tag "$TAG" 2>/dev/null | grep '^-----BEGIN ' | tail -n 1)" != "-----BEGIN PGP SIGNATURE-----" ]; then
    echo "error: tag '$TAG' does not carry an OpenPGP signature — cut it with 'git tag -s' under the default OpenPGP backend (docs/ci.md). Archiving nothing."
    exit 1
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg not found — installing via Homebrew..."
    brew install gnupg
    if ! command -v gpg >/dev/null 2>&1; then
      echo "error: gpg is still not on PATH after 'brew install gnupg' — cannot verify tag '$TAG'. Archiving nothing."
      exit 1
    fi
  fi
  VERIFY_SAVED_GNUPGHOME="${GNUPGHOME:-}"
  VERIFY_GNUPGHOME_WAS_SET="${GNUPGHOME+x}"
  VERIFY_HOME_ACTIVE=""
  VERIFY_GNUPGHOME="$(mktemp -d "${TMPDIR:-/tmp}/gnupg-verify.XXXXXX")"
  chmod 700 "$VERIFY_GNUPGHOME"
  cleanup_verify_home() {
    if [ "${VERIFY_HOME_ACTIVE:-}" = "1" ]; then
      VERIFY_HOME_ACTIVE=0
      rm -rf "$VERIFY_GNUPGHOME"
      if [ "$VERIFY_GNUPGHOME_WAS_SET" = "x" ]; then
        GNUPGHOME="$VERIFY_SAVED_GNUPGHOME"
        export GNUPGHOME
      else
        unset GNUPGHOME
      fi
    fi
  }
  trap 'cleanup_verify_home; exit 130' INT TERM
  trap cleanup_verify_home EXIT
  GNUPGHOME="$VERIFY_GNUPGHOME"
  export GNUPGHOME
  VERIFY_HOME_ACTIVE=1
  if ! IMPORT_DIAG="$(printf '%s\n' "$KEY_ARMOR" | gpg --batch --import 2>&1)"; then
    echo "error: cannot import the release signing key — cannot verify tag '$TAG'. Archiving nothing."
    if [ -n "$IMPORT_DIAG" ]; then
      printf '%s\n' "$IMPORT_DIAG" | sed 's/^/  import: /'
    fi
    exit 1
  fi
  if ! VERIFY_DIAG="$(git -c gpg.program=gpg -c gpg.openpgp.program=gpg -c gpg.ssh.program=/usr/bin/false -c gpg.x509.program=/usr/bin/false verify-tag "$TAG" 2>&1)"; then
    echo "error: tag '$TAG' has no valid release signature — cut it with 'git tag -s' (docs/ci.md). Archiving nothing."
    if [ -n "$VERIFY_DIAG" ]; then
      printf '%s\n' "$VERIFY_DIAG" | sed 's/^/  verify: /'
    fi
    exit 1
  fi
  cleanup_verify_home
  trap - EXIT INT TERM
fi

MARKETING="$(printf '%s' "${VERSION#v}" | cut -d. -f1-3)"
# Sequence is part of the build number: the bare tag is the base (N=0) and
# explicit re-uploads start at .1.
if ! SEQ="$(tag_seq "${VERSION#v}")"; then
  echo "error: tag '$TAG' has an invalid or zero re-upload sequence — explicit re-uploads need .1+ numeric (the bare tag is the base; check for typos like .abc or .0). Archiving nothing."
  exit 1
fi
# Length guard before any arithmetic on SEQ: an over-long value makes
# `[ -gt ]` exit status 2 (treated as false inside `if`, skipping the
# check) and `$(( ))` wrap — failing open with a bogus build number.
# Cap derives from MAX_SEQ (defined at the top).
if [ "${#SEQ}" -gt "${#MAX_SEQ}" ]; then
  echo "error: tag '$TAG' has re-upload sequence $SEQ — out of range (longer than ${#MAX_SEQ} digits; max sequence $MAX_SEQ). Archiving nothing."
  exit 1
fi

BUILD_RUN="${CI_BUILD_NUMBER:-}"
case "$BUILD_RUN" in
  ''|*[!0-9]*)
    echo "error: tag '$TAG' is present but \$CI_BUILD_NUMBER is missing or not numeric — refusing to stamp a guessable build number. Archiving nothing."
    exit 1
    ;;
esac
# Strip leading zeros first ($(( )) would read them as octal), then reject
# 0: a CFBundleVersion of 0 is not uploadable.
BUILD_RUN="$(printf '%s' "$BUILD_RUN" | sed 's/^0*//')"
if [ -z "$BUILD_RUN" ]; then
  echo "error: tag '$TAG' resolved to build number 0, which App Store Connect rejects — refusing to stamp it. Archiving nothing."
  exit 1
fi
# Range check on the normalized value: an over-long value makes `[ -ge ]`
# exit status 2 (treated as false inside `if`, skipping the check) and
# `$(( ))` wrap — failing open with a bogus build number. The ceiling
# derives from STRIDE so the message cannot drift from it; for equal-length
# digit strings the numeric compare below still decides.
if [ "${#BUILD_RUN}" -gt "${#STRIDE}" ] || [ "$BUILD_RUN" -ge "$STRIDE" ]; then
  echo "error: \$CI_BUILD_NUMBER=$BUILD_RUN is not a usable run number (must be 1..$((STRIDE - 1))) — refusing to stamp it. Archiving nothing."
  exit 1
fi
# Channel-banded build number: internal and public are separate Cloud
# workflows with independent run counters, so raw run numbers can order
# backwards across channels for one marketing line (App Store Connect
# rejects a re-upload with a build number at or below the previous one).
# The band index is the highest sequence EVER cut for this marketing line,
# across BOTH namespaces — never just the picked tag's own N. Tags never
# move, so history is monotonic knowledge; banding on the picked tag alone
# breaks the moment a promotion follows a re-upload (release/v0.3.0 after
# internal/v0.3.0.1 was uploaded would band below it). Each sequence number
# N owns a band of 2*STRIDE; public takes the upper half. Reversing channels
# at one N (public before internal) violates the runbook and is rejected by
# ASC, not here.
if [ "$CHANNEL" = "public" ]; then
  CHANBIT=1
else
  CHANBIT=0
fi
HIST_MAX=0
for _t in $(git tag -l "internal/v${MARKETING}" "internal/v${MARKETING}.*" \
  "release/v${MARKETING}" "release/v${MARKETING}.*" 2>/dev/null || true); do
  if _n="$(tag_seq "${_t#*/}")"; then
    # Entries that could never have uploaded contribute no ordering
    # knowledge: explicit-.0 (empty print), over-limit values, and malformed
    # input all skip without disturbing the max. The length pre-check derives
    # from MAX_SEQ (not a second literal) so a future STRIDE change that
    # grows MAX_SEQ cannot silently strand valid history here.
    if [ -n "$_n" ] && [ "${#_n}" -le "${#MAX_SEQ}" ] && [ "$_n" -le "$MAX_SEQ" ] && [ "$_n" -gt "$HIST_MAX" ]; then HIST_MAX="$_n"; fi
  fi
done
# Floor at the picked tag (validated numeric above): a listing hiccup must
# never band below the tag being stamped — worst case is the old behavior.
if [ "$SEQ" -gt "$HIST_MAX" ]; then HIST_MAX="$SEQ"; fi
# Length guard first: beyond MAX_SEQ's digit count the value may exceed the
# shell's integer range, in which case `[ -gt ]` errors (status 2, silently
# skipped in an `if` condition) and $(( )) wraps — failing open. MAX_SEQ is
# 10736.
if [ "${#HIST_MAX}" -gt "${#MAX_SEQ}" ] || [ "$HIST_MAX" -gt "$MAX_SEQ" ]; then
  echo "error: marketing $MARKETING already reached re-upload sequence $HIST_MAX — the banded build would exceed App Store Connect's 2^31-1 limit (max sequence $MAX_SEQ). Archiving nothing."
  exit 1
fi
BUILD="$(( (HIST_MAX * 2 + CHANBIT) * STRIDE + BUILD_RUN ))"

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
