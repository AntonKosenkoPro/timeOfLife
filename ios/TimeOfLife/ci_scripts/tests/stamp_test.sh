#!/bin/sh
# Stamp-script harness (manual-tag-releases, review finding: stamp logic had
# no automated coverage — a wrong build number surfaces only at ASC upload).
#
# Local-only, never runs in CI: exercises ci_post_clone.sh against a scratch
# copy of project.yml + generated plists via TAG_OVERRIDE (and real local
# tags for the points-at paths — created and deleted here, never pushed).
# Requires: xcodegen on PATH (matches XCODEGEN_PIN), git repo, bash or sh.
#
# Usage: sh ios/TimeOfLife/ci_scripts/tests/stamp_test.sh
set -e

cd "$(dirname "$0")/../.."
[ -f project.yml ] || { echo "FAIL: harness must run with ios/TimeOfLife as the project root"; exit 1; }
SCRIPT="ci_scripts/ci_post_clone.sh"
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stamp-test.XXXXXX")"
PASS=0
FAIL=0

tracked="project.yml TimeOfLife/Configuration/Info.plist LifioLiveActivities/Info.plist"
for f in $tracked; do
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done
CREATED_TAGS=""
restore() {
  for f in $tracked; do
    cp "$BACKUP_DIR/$f" "$f"
  done
  xcodegen generate >/dev/null 2>&1 || true
  for t in $CREATED_TAGS; do
    git tag -d "$t" >/dev/null 2>&1 || true
  done
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

mktag() { git tag "$1" HEAD 2>/dev/null; CREATED_TAGS="$CREATED_TAGS $1"; }

command -v xcodegen >/dev/null 2>&1 || { echo "FAIL: xcodegen not on PATH"; exit 1; }
sh -n "$SCRIPT" || { echo "FAIL: syntax"; exit 1; }

# 1. No tag: exit 0, versions untouched.
expect 0 "no tag leaves dummy" "leaving project.yml versions untouched" \
  env TAG_OVERRIDE="" CI_BUILD_NUMBER=9 CI_WORKFLOW="" sh "$SCRIPT"

# 2. Internal stamp: marketing/build/channel + unanimity.
# Banded builds: internal N=1 → (1*2+0)*100000+RUN.
# Bare tag is the base (N=0): build is just the run number.
expect 0 "internal stamps 0.2.7/42" "Version unanimity OK: marketing=0.2.7 build=42 channel=internal" \
  env TAG_OVERRIDE="internal/v0.2.7" CI_BUILD_NUMBER=42 CI_WORKFLOW="" sh "$SCRIPT"

# 3. Release .n stamp: N=2 public → (2*2+1)*100000+RUN.
expect 0 "release .2 stamps 0.3.0/500003" "Version unanimity OK: marketing=0.3.0 build=500003 channel=public" \
  env TAG_OVERRIDE="release/v0.3.0.2" CI_BUILD_NUMBER=3 CI_WORKFLOW="" sh "$SCRIPT"

# 4. Bad grammar / zero run / huge SEQ: exit 1.
expect 1 "bad semver refused" "not <namespace>/vM.m.p" \
  env TAG_OVERRIDE="internal/v1.0" CI_BUILD_NUMBER=5 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "zero run refused" "build number 0" \
  env TAG_OVERRIDE="internal/v0.2.7" CI_BUILD_NUMBER=0 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "huge sequence refused" "2^31-1" \
  env TAG_OVERRIDE="internal/v0.3.0.99999999999999999999" CI_BUILD_NUMBER=5 CI_WORKFLOW="" sh "$SCRIPT"

# 5. Real-tag paths: same-namespace highest-.n wins; promotion pair picks by workflow.
mktag internal/v0.0.1; mktag internal/v0.0.1.2
expect 0 "same-namespace pair stamps highest .n" "Version unanimity OK: marketing=0.0.1 build=400005 channel=internal" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v0.0.4; mktag internal/v0.0.4.1
expect 0 "bare vs .1 stamps .1" "Version unanimity OK: marketing=0.0.4 build=200005 channel=internal" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v0.0.5; mktag internal/v0.0.5.0
expect 1 "explicit .0 in pair aborts" "sequences start at 1" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v0.0.2; mktag internal/v0.0.2.999999
expect 1 "oversize sequence in pair aborts" "out of range" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v0.0.1; mktag release/v0.0.1
expect 0 "promotion pair picks internal" "channel=internal" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v0.0.1; mktag release/v0.0.1
expect 0 "promotion pair picks public" "channel=public" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v0.2.7; mktag release/v0.3.0
expect 1 "mismatched pair aborts" "multiple marketing versions" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag release/v0.0.1
expect 1 "lone cross-namespace tag aborts" "wrong channel" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""

# 6. Ordering across a realistic sequence (dogfood → public → re-upload).
b1="$(TAG_OVERRIDE="internal/v0.3.0" CI_BUILD_NUMBER=45 CI_WORKFLOW="" sh "$SCRIPT" >/dev/null 2>&1; grep -m1 'CFBundleVersion:' project.yml | grep -o '[0-9]*')"
cp "$BACKUP_DIR/project.yml" project.yml
b2="$(TAG_OVERRIDE="release/v0.3.0" CI_BUILD_NUMBER=3 CI_WORKFLOW="" sh "$SCRIPT" >/dev/null 2>&1; grep -m1 'CFBundleVersion:' project.yml | grep -o '[0-9]*')"
cp "$BACKUP_DIR/project.yml" project.yml
b3="$(TAG_OVERRIDE="internal/v0.3.0.2" CI_BUILD_NUMBER=90 CI_WORKFLOW="" sh "$SCRIPT" >/dev/null 2>&1; grep -m1 'CFBundleVersion:' project.yml | grep -o '[0-9]*')"
cp "$BACKUP_DIR/project.yml" project.yml
if [ "$b1" -lt "$b2" ] && [ "$b2" -lt "$b3" ]; then
  echo "ok: banded builds increase ($b1 < $b2 < $b3)"; PASS=$((PASS + 1))
else
  echo "FAIL: banded builds not increasing ($b1, $b2, $b3)"; FAIL=$((FAIL + 1))
fi

echo "---"
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
