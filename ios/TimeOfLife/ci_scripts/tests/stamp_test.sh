#!/bin/sh
# Stamp-script harness (manual-tag-releases, review finding: stamp logic had
# no automated coverage — a wrong build number surfaces only at ASC upload).
#
# Runs in CI (ios.yml lint-build-test, after SwiftLint) and locally:
# exercises ci_post_clone.sh against a scratch copy of project.yml +
# generated plists via TAG_OVERRIDE (and real local tags for the points-at
# paths — created and deleted here, never pushed; signed with a throwaway
# key via STAMP_SIGNING_KEY since the script verifies signatures). Restores everything on
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
# The signing setup below exports GNUPGHOME; save the caller's so restore()
# puts it back (the harness is its own process, but sourced runs and later
# gpg use inside it must not see the deleted throwaway home).
HARNESS_GNUPGHOME_WAS_SET="${GNUPGHOME+x}"
HARNESS_GNUPGHOME_SAVED="${GNUPGHOME:-}"

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
  if [ "$HARNESS_GNUPGHOME_WAS_SET" = "x" ]; then
    GNUPGHOME="$HARNESS_GNUPGHOME_SAVED"; export GNUPGHOME
  else
    unset GNUPGHOME
  fi
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

# Throwaway signing key for the real-tag cases: the script under test now
# verifies tag signatures, so harness-created tags must be signed — with a
# throwaway key (never the developer's), selected via STAMP_SIGNING_KEY.
# gpg is brew-installed when missing and its absence is a hard FAIL, never
# a skip: the signature cases gate releases and must always run.
HAVE_GPG=0
HARNESS_KEYID=""
setup_signing() {
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg not found — installing via Homebrew..."
    brew install gnupg || { echo "FAIL: cannot install gnupg — signature cases gate releases and must never skip"; exit 1; }
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "FAIL: gpg unavailable — refusing to skip signature cases (they gate releases)"
    exit 1
  fi
  export GNUPGHOME="$BACKUP_DIR/gnupg"
  mkdir -p -m 700 "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  gpg --batch --gen-key <<'EOF' 2>/dev/null || { echo "FAIL: cannot generate throwaway signing key"; exit 1; }
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Name-Email: harness@local.invalid
Expire-Date: 1d
%commit
EOF
  HARNESS_KEYID="$(gpg --batch --with-colons --list-secret-keys harness@local.invalid 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
  [ -n "$HARNESS_KEYID" ] || { echo "FAIL: throwaway key has no fingerprint"; exit 1; }
  STAMP_SIGNING_KEY="$BACKUP_DIR/harness-signing.pub"
  export STAMP_SIGNING_KEY
  gpg --batch --armor --export harness@local.invalid > "$STAMP_SIGNING_KEY" 2>/dev/null || { echo "FAIL: cannot export throwaway public key"; exit 1; }
  HAVE_GPG=1
}
mktag() {
  # Never touch a pre-existing tag: devs reuse names like internal/v9.9.1,
  # and silently stamping (then deleting) a real tag would be destructive.
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite/delete a real tag (delete it yourself if it is scratch)"; exit 1
  fi
  # Signed with the throwaway key (explicit -c: never the developer's key,
  # regardless of their tag.gpgsign/user.signingkey settings; gpg.format is
  # forced to OpenPGP so an inherited gpg.format=ssh cannot divert signing).
  git -c tag.gpgsign=false -c gpg.format=openpgp -c user.signingkey="$HARNESS_KEYID" tag -s -m "harness $1" "$1" HEAD 2>/dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}
mktag_unsigned() {
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite it"; exit 1
  fi
  # Explicitly unsigned (tag.gpgsign=false defeats a developer-global
  # tag.gpgsign=true, which would otherwise sign with their real key).
  git -c tag.gpgsign=false tag -a -m "harness unsigned $1" "$1" HEAD 2>/dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}
mktag_lightweight() {
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite it"; exit 1
  fi
  # Lightweight (no -a/-s/-m): a bare ref with no tag object and no
  # signature — must be refused like an unsigned tag.
  git -c tag.gpgsign=false tag "$1" HEAD 2>/dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}
mktag_at() { # mktag_at <tag> <commit>: throwaway-signed at an ancestor commit
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite it"; exit 1
  fi
  git -c tag.gpgsign=false -c gpg.format=openpgp -c user.signingkey="$HARNESS_KEYID" tag -s -m "harness $1" "$1" "$2" 2>/dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}

command -v xcodegen >/dev/null 2>&1 || { echo "FAIL: xcodegen not on PATH"; exit 1; }
sh -n "$SCRIPT" || { echo "FAIL: syntax"; exit 1; }

# Isolation preflight FIRST (before every case, including the TAG_OVERRIDE
# ones in sections 1-4b): history banding reads `git tag -l` regardless of
# TAG_OVERRIDE, so ANY local tag for the harness versions — anywhere in
# history, not just at HEAD — shifts HIST_MAX and corrupts the exact build
# assertions with misleading "missing ..." failures. The versions use the
# v9.9.* namespace, which real releases never touch; fail fast if anything
# is there anyway. The HEAD check guards the points-at enumeration used by
# the real-tag cases below.
if git tag -l "internal/v9.9.*" "release/v9.9.*" | grep -q .; then
  echo "FAIL: local tags already exist for the harness v9.9.* versions ($(git tag -l "internal/v9.9.*" "release/v9.9.*" | tr '\n' ' ')) — run this harness from a checkout without them (or a scratch worktree)"; exit 1
fi
if git tag --points-at HEAD | grep -qE '^(internal|release)/'; then
  echo "FAIL: HEAD already carries an iOS release tag — run this harness from an untagged commit (or a scratch worktree)"; exit 1
fi

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
# 4c. MAX_SEQ boundary from the picked-tag side (MAX_SEQ = 10736):
# the largest accepted sequence stamps just under 2^31-1, one more aborts.
expect 0 "max sequence 10736 accepted" "Version unanimity OK: marketing=9.9.0 build=2147200005 channel=internal" \
  env TAG_OVERRIDE="internal/v9.9.0.10736" CI_BUILD_NUMBER=5 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "sequence 10737 refused" "already reached re-upload sequence" \
  env TAG_OVERRIDE="internal/v9.9.9.10737" CI_BUILD_NUMBER=5 CI_WORKFLOW="" sh "$SCRIPT"

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
# Real-tag sections below need the throwaway signing key (the script under
# test verifies signatures on the non-override path). setup_signing fails
# closed where gpg cannot be provided — the signature cases gate releases
# and must never skip.
setup_signing
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
# 5b. History filter: a well-formed but over-limit entry that is NOT the
# picked tag must be skipped, not fatal. Pair shares one marketing line;
# Public picks release/v9.9.5 (SEQ 0) while internal/v9.9.5.99999 poisons
# history — the filter skips it and bands (0*2+1)*STRIDE+RUN. The old code
# exited 1 here for every future stamp of the line, forever.
mktag release/v9.9.5; mktag internal/v9.9.5.99999
expect 0 "over-limit history entry skipped" "Version unanimity OK: marketing=9.9.5 build=100005 channel=public" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# Companion: an in-range history entry still lifts the band (10736 from
# history, public channel → (10736*2+1)*STRIDE+RUN, just under 2^31-1).
mktag release/v9.9.5; mktag internal/v9.9.5.10736
expect 0 "in-range history sequence bands" "Version unanimity OK: marketing=9.9.5 build=2147300005 channel=public" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Public Release" sh "$SCRIPT"
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
# 5c. Signature gate: an unsigned tag that is otherwise perfect (right
# namespace, valid grammar) must be refused before anything is stamped.
mktag_unsigned internal/v9.9.0
expect 1 "unsigned tag refused" "no valid release signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5d. Lightweight tags are bare refs (no tag object, no signature) and must
# be refused like unsigned ones.
mktag_lightweight internal/v9.9.0
expect 1 "lightweight tag refused" "no valid release signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5e. Wrong-key tags must be refused: the scratch tag is signed by the
# throwaway key but verified against the repo release key (STAMP_SIGNING_KEY
# unset selects the default anchor).
mktag internal/v9.9.0
expect 1 "wrong-key tag refused" "no valid release signature" \
  env -u TAG_OVERRIDE -u STAMP_SIGNING_KEY CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5f. Tag-to-HEAD binding: a validly signed tag that is NOT at HEAD must not
# stamp — the build keeps the dev dummy. Needs a parent commit; skipped
# loudly (not silently) where history is too shallow for one.
if PARENT_BIND="$(git rev-parse --verify HEAD~1 2>/dev/null)"; then
  mktag_at internal/v9.9.0 "$PARENT_BIND"
  expect 0 "signed tag off HEAD does not stamp" "leaving project.yml versions untouched" \
    env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
  for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
else
  echo "SKIP: tag-to-HEAD binding case needs a parent commit (shallow checkout?)"
fi

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
