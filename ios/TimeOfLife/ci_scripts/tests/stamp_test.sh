#!/bin/sh
# Stamp-script harness (manual-tag-releases, review finding: stamp logic had
# no automated coverage — a wrong build number surfaces only at ASC upload).
#
# Runs in CI (ios.yml lint-build-test, after SwiftLint) and locally:
# exercises ci_post_clone.sh against a scratch copy of project.yml +
# generated plists via TAG_OVERRIDE (and real local tags for the points-at
# paths — created and deleted here, never pushed). Restores everything on
# exit, so later CI steps see a clean tree.
# Requires: xcodegen on PATH (matches XCODEGEN_PIN), git repo, bash or sh.
#
# Usage: sh ios/TimeOfLife/ci_scripts/tests/stamp_test.sh
set -e

cd "$(dirname "$0")/../.."
[ -f project.yml ] || { echo "FAIL: harness must run with ios/TimeOfLife as the project root"; exit 1; }
SCRIPT="ci_scripts/ci_post_clone.sh"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO_ROOT" ] || { echo "FAIL: not inside a git work tree"; exit 1; }
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stamp-test.XXXXXX")"
PASS=0
FAIL=0

tracked="project.yml TimeOfLife/Configuration/Info.plist LifioLiveActivities/Info.plist"
for f in $tracked; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done
CREATED_TAGS=""
# Hermetic origin for the real-tag cases below: the script under test runs
# `git fetch --tags origin`, which otherwise needs the network and writes
# remote tags into the developer's repo. Point origin at a throwaway local
# bare clone instead (restored by restore()).
ORIGIN_MODE=""
ORIGIN_URL=""
setup_test_origin() {
  TEST_ORIGIN="$BACKUP_DIR/origin.git"
  git clone --quiet --bare "$REPO_ROOT" "$TEST_ORIGIN" || { echo "FAIL: cannot clone throwaway origin"; exit 1; }
  if ORIGIN_URL="$(git remote get-url origin 2>/dev/null)"; then
    ORIGIN_MODE="set-url"
    git remote set-url origin "$TEST_ORIGIN"
  else
    ORIGIN_MODE="add"
    git remote add origin "$TEST_ORIGIN"
  fi
}
restore() {
  for f in $tracked; do
    cp "$BACKUP_DIR/$f" "$f"
  done
  xcodegen generate >/dev/null 2>&1 || true
  for t in $CREATED_TAGS; do
    git tag -d "$t" >/dev/null 2>&1 || true
  done
  case "$ORIGIN_MODE" in
    add) git remote remove origin 2>/dev/null || true ;;
    set-url) git remote set-url origin "$ORIGIN_URL" 2>/dev/null || true ;;
  esac
  rm -rf "$BACKUP_DIR"
}
trap restore EXIT INT TERM

expect() { # expect <want-exit> <desc> [want-grep] -- cmd...
  want="$1"; desc="$2"; want_grep="$3"; shift 3
  # `if` guards the capture: a nonzero exit inside $() would trip `set -e`.
  if out="$("$@" 2>&1)"; then code=0; else code=$?; fi
  if [ "$code" != "$want" ]; then
    echo "FAIL: $desc — exit $code, want $want"; printf '%s\n' "$out" | tail -3; FAIL=$((FAIL + 1)); return 0
  fi
  if [ -n "$want_grep" ] && ! printf '%s\n' "$out" | grep -q "$want_grep"; then
    echo "FAIL: $desc — missing '$want_grep'"; printf '%s\n' "$out" | tail -3; FAIL=$((FAIL + 1)); return 0
  fi
  echo "ok: $desc"; PASS=$((PASS + 1))
}

mktag() {
  # Never touch a pre-existing tag: devs reuse names like internal/v9.9.1,
  # and silently stamping (then deleting) a real tag would be destructive.
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite/delete a real tag (delete it yourself if it is scratch)"; exit 1
  fi
  git tag "$1" HEAD 2>/dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}

command -v xcodegen >/dev/null 2>&1 || { echo "FAIL: xcodegen not on PATH"; exit 1; }
sh -n "$SCRIPT" || { echo "FAIL: syntax"; exit 1; }

# 1. No tag: exit 0, versions untouched.
expect 0 "no tag leaves dummy" "leaving project.yml versions untouched" \
  env TAG_OVERRIDE="" CI_BUILD_NUMBER=9 CI_WORKFLOW="" sh "$SCRIPT"

# 2. Internal stamp: marketing/build/channel + unanimity.
# Banded builds: internal N=1 → (1*2+0)*100000+RUN.
# Bare tag is the base (N=0): build is just the run number.
expect 0 "internal stamps 9.9.7/42" "Version unanimity OK: marketing=9.9.7 build=42 channel=internal" \
  env TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=42 CI_WORKFLOW="" sh "$SCRIPT"

# 3. Release .n stamp: N=2 public → (2*2+1)*100000+RUN.
expect 0 "release .2 stamps 9.9.3/500003" "Version unanimity OK: marketing=9.9.3 build=500003 channel=public" \
  env TAG_OVERRIDE="release/v9.9.3.2" CI_BUILD_NUMBER=3 CI_WORKFLOW="" sh "$SCRIPT"

# 4. Bad grammar / zero run / huge SEQ: exit 1.
expect 1 "bad semver refused" "not <namespace>/vM.m.p" \
  env TAG_OVERRIDE="internal/v1.0" CI_BUILD_NUMBER=5 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "zero run refused" "build number 0" \
  env TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=0 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "huge sequence refused" "out of range" \
  env TAG_OVERRIDE="internal/v9.9.3.99999999999999999999" CI_BUILD_NUMBER=5 CI_WORKFLOW="" sh "$SCRIPT"

# 4b. New guard paths: padded / out-of-range run number, duplicate sequence.
expect 0 "padded run number accepted" "build=42" \
  env TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=000042 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "over-range run number refused" "not a usable run number" \
  env TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=100000 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "missing run refused" "CI_BUILD_NUMBER is missing" \
  env -u CI_BUILD_NUMBER TAG_OVERRIDE="internal/v9.9.7" CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "non-numeric run refused" "CI_BUILD_NUMBER is missing or not numeric" \
  env TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=42x CI_WORKFLOW="" sh "$SCRIPT"

# 5. Real-tag paths (hermetic: origin points at the throwaway bare clone,
# so no network and no writes to the developer's remote refs): same-namespace
# highest-.n wins; promotion pair picks by workflow.
setup_test_origin
# Isolation preflight: the history-aware banding reads `git tag -l` for the
# marketing versions below (not just tags at HEAD), and the fetch inside the
# script re-imports real tags from the throwaway origin — so ANY local tag
# for the harness versions, anywhere in history, shifts HIST_MAX and flips
# the exact build assertions. The versions use the v9.9.* namespace, which
# real releases never touch; fail fast if anything is there anyway instead
# of leaving a trap for the next maintainer.
if git tag -l "internal/v9.9.*" "release/v9.9.*" | grep -q .; then
  echo "FAIL: local tags already exist for the harness v9.9.* versions ($(git tag -l "internal/v9.9.*" "release/v9.9.*" | tr '\n' ' ')) — run this harness from a checkout without them (or a scratch worktree)"; exit 1
fi
if git tag --points-at HEAD | grep -qE '^(internal|release)/'; then
  echo "FAIL: HEAD already carries an iOS release tag — run this harness from an untagged commit (or a scratch worktree)"; exit 1
fi
mktag internal/v9.9.1; mktag internal/v9.9.1.2
expect 0 "same-namespace pair stamps highest .n" "Version unanimity OK: marketing=9.9.1 build=400005 channel=internal" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.4; mktag internal/v9.9.4.1
expect 0 "bare vs .1 stamps .1" "Version unanimity OK: marketing=9.9.4 build=200005 channel=internal" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.5; mktag internal/v9.9.5.0
expect 1 "explicit .0 in pair aborts" "invalid or zero re-upload sequence" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.2; mktag internal/v9.9.2.999999
expect 1 "oversize sequence in pair aborts" "out of range" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.8.1; mktag internal/v9.9.8.01
expect 1 "duplicate sequence aborts" "duplicate re-upload sequence" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.1; mktag release/v9.9.1
expect 0 "promotion pair picks internal" "channel=internal" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.1; mktag release/v9.9.1
expect 0 "promotion pair picks public" "channel=public" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.7; mktag release/v9.9.3
expect 1 "mismatched pair aborts" "multiple marketing versions" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag release/v9.9.1
expect 1 "lone cross-namespace tag aborts" "wrong channel" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
expect 1 "unrecognized workflow fails closed" "not a pinned release workflow" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Renamed Workflow" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""

# 6. Ordering across a realistic sequence (dogfood → public → re-upload).
# Each run is asserted like the cases above (exit + unanimity line): a
# failed stamp leaves the dummy behind, and comparing raw CFBundleVersion
# values would mask a mixed failure as long as they still order.
stamp() { # stamp <override> <run> <workflow> <want-exit> <want-grep> <desc>
  if out="$(TAG_OVERRIDE="$1" CI_BUILD_NUMBER="$2" CI_WORKFLOW="$3" sh "$SCRIPT" 2>&1)"; then code=0; else code=$?; fi
  if [ "$code" != "$4" ]; then
    echo "FAIL: $6 — exit $code, want $4"; printf '%s\n' "$out" | tail -3; FAIL=$((FAIL + 1)); return 0
  fi
  if [ -n "$5" ] && ! printf '%s\n' "$out" | grep -q "$5"; then
    echo "FAIL: $6 — missing '$5'"; printf '%s\n' "$out" | tail -3; FAIL=$((FAIL + 1)); return 0
  fi
  echo "ok: $6"; PASS=$((PASS + 1))
}
stamp "internal/v9.9.3" 45 "" 0 "Version unanimity OK" "ordering run b1 stamps"
# `|| true`: under `set -e` a missing key would abort the script here —
# the empty check below must stay reachable to print the FAIL diagnostic.
b1="$(grep -m1 'CFBundleVersion:' project.yml | grep -o '[0-9]*' || true)"
cp "$BACKUP_DIR/project.yml" project.yml
stamp "release/v9.9.3" 3 "" 0 "Version unanimity OK" "ordering run b2 stamps"
b2="$(grep -m1 'CFBundleVersion:' project.yml | grep -o '[0-9]*' || true)"
cp "$BACKUP_DIR/project.yml" project.yml
stamp "internal/v9.9.3.2" 90 "" 0 "Version unanimity OK" "ordering run b3 stamps"
b3="$(grep -m1 'CFBundleVersion:' project.yml | grep -o '[0-9]*' || true)"
cp "$BACKUP_DIR/project.yml" project.yml
if [ -z "$b1" ] || [ -z "$b2" ] || [ -z "$b3" ] || [ "$b1" = "0" ] || [ "$b2" = "0" ] || [ "$b3" = "0" ]; then
  echo "FAIL: banded builds unreadable or dummy ($b1, $b2, $b3)"; FAIL=$((FAIL + 1))
elif [ "$b1" -lt "$b2" ] && [ "$b2" -lt "$b3" ]; then
  echo "ok: banded builds increase ($b1 < $b2 < $b3)"; PASS=$((PASS + 1))
else
  echo "FAIL: banded builds not increasing ($b1, $b2, $b3)"; FAIL=$((FAIL + 1))
fi
# 7. Band follows history, not just HEAD: an internal re-upload cut on an
# ancestor commit must lift a later same-commit promotion above it, or App
# Store Connect rejects the public upload. Needs a parent commit; skipped
# loudly (not silently) where history is too shallow for one.
if PARENT="$(git rev-parse --verify HEAD~1 2>/dev/null)"; then
  mktag_at() {
    if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
      echo "FAIL: tag '$1' already exists locally — refusing to overwrite it"; exit 1
    fi
    git tag "$1" "$2" 2>/dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }; CREATED_TAGS="$CREATED_TAGS $1"; }
  mktag_at internal/v9.9.6.1 "$PARENT"
  mktag internal/v9.9.6; mktag release/v9.9.6
  expect 0 "promotion after ancestor re-upload bands above it" "build=300007" \
    env -u TAG_OVERRIDE CI_BUILD_NUMBER=7 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
  for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
else
  echo "SKIP: history-aware band case needs a parent commit (shallow checkout?)"
fi

echo "---"
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
