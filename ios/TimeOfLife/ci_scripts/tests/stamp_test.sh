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
CREATED_BRANCHES=""
# Hermetic origin for the real-tag cases below: the script under test runs
# `git fetch --tags origin`, which otherwise needs the network and writes
# remote tags into the developer's repo. Point origin at a throwaway local
# bare clone instead (restored by restore()).
ORIGIN_MODE=""
ORIGIN_URL=""
# Recorded independently (set right after snapshotting, BEFORE mutating):
# a signal aborting the mutation itself must still see the URL restored.
ORIGIN_URL_RECORDED=""
ORIGIN_MAIN_SYMREF=""
ORIGIN_MAIN_VALUE=""
# Set to 1 as the LAST line of setup_test_origin: "absent before" must never
# be confused with "recorded absent", or restore() would delete unrecorded
# caller state on early exits (preflight, clone failure).
ORIGIN_MAIN_RECORDED=""
ANCHOR_GOOD=""
ANCHOR_NONE=""
ANCHOR_BAD=""
setup_test_origin() {
  TEST_ORIGIN="$BACKUP_DIR/origin.git"
  # Capability probe: every ref removal below uses --no-deref (plain -d on a
  # symref destroys its TARGET branch). An unsupported flag must fail here
  # loudly — never silently skip into a dereferencing fallback mid-run.
  git update-ref refs/stamp-test/probe HEAD 2>/dev/null || { echo "FAIL: cannot write scratch ref"; exit 1; }
  if ! git update-ref --no-deref -d refs/stamp-test/probe 2>/dev/null; then
    git update-ref -d refs/stamp-test/probe 2>/dev/null || true
    echo "FAIL: git update-ref --no-deref unsupported — ref-safety handling must never silently skip"; exit 1
  fi
  git clone --quiet --bare "$REPO_ROOT" "$TEST_ORIGIN" || { echo "FAIL: cannot clone throwaway origin"; exit 1; }
  # The script under test fetches refs/heads/main explicitly (non-forced):
  # seed the throwaway main from the existing tracking ref when it resolves
  # (a HEAD seed breaks whenever origin/main is ahead of HEAD — the refspec
  # then rejects as non-fast-forward and the fetch fails 3x), else HEAD.
  if ! git --git-dir="$TEST_ORIGIN" show-ref --verify --quiet refs/heads/main; then
    SEED_MAIN="$(git rev-parse --verify --quiet refs/remotes/origin/main || git rev-parse --verify HEAD)"
    git --git-dir="$TEST_ORIGIN" update-ref refs/heads/main "$SEED_MAIN" || { echo "FAIL: cannot seed throwaway origin main"; exit 1; }
  fi
  # Snapshot the remote URL/mode BEFORE mutating, and record immediately:
  # a signal aborting the mutation command itself must still see the URL
  # restored (the mutation is what the flag protects, not its success).
  if ORIGIN_URL="$(git remote get-url origin 2>/dev/null)"; then
    ORIGIN_MODE="set-url"
  else
    ORIGIN_MODE="add"
    ORIGIN_URL=""
  fi
  ORIGIN_URL_RECORDED=1
  case "$ORIGIN_MODE" in
    set-url) git remote set-url origin "$TEST_ORIGIN" ;;
    add) git remote add origin "$TEST_ORIGIN" ;;
  esac
  # Proven pollution record: the script under test fetches refs/heads/main
  # explicitly, overwriting refs/remotes/origin/main HERE on every
  # non-override run. Snapshot this one ref (symref/value/absent) for
  # restore() — plumbing only, no network, no other refs touched.
  ORIGIN_MAIN_SYMREF="$(git symbolic-ref -q refs/remotes/origin/main 2>/dev/null || true)"
  ORIGIN_MAIN_VALUE="$(git rev-parse --verify --quiet refs/remotes/origin/main 2>/dev/null || true)"
  # Drop the local tracking ref without ever following it (recorded above,
  # restored by restore()): later fetches re-create it direct, so no fetch
  # can mutate a caller referent through a symbolic link, and the non-forced
  # refspec can never hit a non-fast-forward reject. Plain `update-ref -d`
  # on a symref destroys its TARGET branch — hence --no-deref (fail-closed
  # inside the helper, absent-tolerant).
  drop_origin_main
  ORIGIN_MAIN_RECORDED=1
}
restore() {
  for f in $tracked; do
    cp "$BACKUP_DIR/$f" "$f"
  done
  xcodegen generate >/dev/null 2>&1 || true
  for t in $CREATED_TAGS; do
    git tag -d "$t" >/dev/null 2>&1 || true
  done
  for b in $CREATED_BRANCHES; do
    git branch -D "$b" >/dev/null 2>&1 || true
  done
  # Undo recorded origin side effects. URL and tracking have SEPARATE
  # flags: the URL is snapshotted before its mutation (a signal aborting the
  # mutation itself must still see it restored), while the tracking ref is
  # recorded only once setup completes its own mutations.
  if [ "$ORIGIN_URL_RECORDED" = "1" ]; then
    case "$ORIGIN_MODE" in
      add) git remote remove origin 2>/dev/null || true ;;
      set-url) git remote set-url origin "$ORIGIN_URL" 2>/dev/null || true ;;
    esac
  fi
  if [ "$ORIGIN_MAIN_RECORDED" = "1" ]; then
    # Clear through --no-deref first so a leftover symbolic link can never
    # route this restore into a caller referent; then rebuild the recorded
    # shape (symbolic/direct/absent) — this one ref only.
    if ! git update-ref --no-deref -d refs/remotes/origin/main 2>/dev/null; then
      if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
        echo "WARN: cannot clear refs/remotes/origin/main without dereferencing — leaving for the next fetch"
      fi
    fi
    if [ -n "$ORIGIN_MAIN_SYMREF" ]; then
      git symbolic-ref refs/remotes/origin/main "$ORIGIN_MAIN_SYMREF" 2>/dev/null || true
    elif [ -n "$ORIGIN_MAIN_VALUE" ]; then
      git update-ref refs/remotes/origin/main "$ORIGIN_MAIN_VALUE" 2>/dev/null || true
    fi
  fi
  if [ "$HARNESS_GNUPGHOME_WAS_SET" = "x" ]; then
    GNUPGHOME="$HARNESS_GNUPGHOME_SAVED"; export GNUPGHOME
  else
    unset GNUPGHOME
  fi
  # The throwaway key spawns a gpg-agent on GNUPGHOME inside BACKUP_DIR:
  # kill it (throwaway home only, never the caller's) before deleting.
  if [ -d "$BACKUP_DIR/gnupg" ]; then
    GNUPGHOME="$BACKUP_DIR/gnupg" gpgconf --kill all >/dev/null 2>&1 || true
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

# Refusal-ordering guard: the signature cases below must fail BEFORE
# anything is stamped. snapshot_files hashes every file the script stamps;
# assert_unstamped fails the harness if a refusal mutated them.
snapshot_files() {
  # Reuses $tracked (single source of truth for the files the script stamps).
  git hash-object $tracked 2>/dev/null | tr '\n' ' '
}
assert_unstamped() { # assert_unstamped <desc>
  if [ "$(snapshot_files)" != "$SNAP_BEFORE" ]; then
    echo "FAIL: $1 — files changed despite refusal"; FAIL=$((FAIL + 1)); return 0
  fi
  echo "ok: $1"; PASS=$((PASS + 1))
}
reset_origin_main() { # reset_origin_main <commit>: rotate the throwaway
  # main and drop the local tip so the next script fetch re-reads it (the
  # non-forced refspec would otherwise reject sibling rotations as
  # non-fast-forward). Order-proof where a linear chain would not be. The
  # recorded original is restored by restore() at exit.
  git --git-dir="$TEST_ORIGIN" update-ref refs/heads/main "$1" || { echo "FAIL: cannot rotate throwaway origin main"; exit 1; }
  drop_origin_main
}
# Drop a tracking ref without ever following it: plain `update-ref -d` on a
# symbolic ref destroys its TARGET branch, and a later fetch through a
# surviving symref would rewrite the caller referent. --no-deref removes the
# link itself in every shape. Absent is fine; any other failure is fatal —
# an unsupported --no-deref must never silently skip (the fetch would then
# dereference into caller state).
drop_origin_main() {
  if ! git update-ref --no-deref -d refs/remotes/origin/main 2>/dev/null; then
    if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
      echo "FAIL: cannot drop refs/remotes/origin/main without dereferencing"; exit 1
    fi
  fi
}

# Throwaway signing key for the real-tag cases (never the developer's),
# selected via STAMP_SIGNING_KEY. gpg absence is a hard FAIL, never a skip.
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
  # gpg diagnostics print with the FAIL line (success stays quiet); params
  # go via a file (a heredoc would swallow the multi-line if-branch).
  GENKEY_PARAMS="$BACKUP_DIR/genkey.params"
  cat >"$GENKEY_PARAMS" <<'EOF'
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Name-Email: harness@local.invalid
Expire-Date: 1d
%commit
EOF
  GENKEY_LOG="$BACKUP_DIR/genkey.err"
  if ! gpg --batch --gen-key "$GENKEY_PARAMS" 2>"$GENKEY_LOG"; then
    echo "FAIL: cannot generate throwaway signing key"
    sed 's/^/  /' "$GENKEY_LOG" 2>/dev/null || true
    exit 1
  fi
  HARNESS_KEYID="$(gpg --batch --with-colons --list-secret-keys harness@local.invalid 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
  [ -n "$HARNESS_KEYID" ] || { echo "FAIL: throwaway key has no fingerprint"; exit 1; }
  STAMP_SIGNING_KEY="$BACKUP_DIR/harness-signing.pub"
  export STAMP_SIGNING_KEY
  if ! gpg --batch --armor --export harness@local.invalid > "$STAMP_SIGNING_KEY" 2>"$BACKUP_DIR/export.err"; then
    echo "FAIL: cannot export throwaway public key"
    sed 's/^/  /' "$BACKUP_DIR/export.err" 2>/dev/null || true
    exit 1
  fi
}
# Extra format-gate fixtures: a second throwaway OpenPGP key (wrong
# anchor), an SSH keypair (non-OpenPGP tags), and an attacker gitconfig
# trusting it. All ephemeral, no passphrases/prompts (stdin /dev/null).
setup_format_fixtures() {
  WRONG_PARAMS="$BACKUP_DIR/genkey-wrong.params"
  cat >"$WRONG_PARAMS" <<'EOF'
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Name-Email: wrong@local.invalid
Expire-Date: 1d
%commit
EOF
  if ! gpg --batch --gen-key "$WRONG_PARAMS" 2>"$BACKUP_DIR/genkey-wrong.err"; then
    echo "FAIL: cannot generate wrong-anchor key"
    sed 's/^/  /' "$BACKUP_DIR/genkey-wrong.err" 2>/dev/null || true
    exit 1
  fi
  if ! gpg --batch --armor --export wrong@local.invalid > "$BACKUP_DIR/wrong-anchor.pub" 2>"$BACKUP_DIR/export-wrong.err"; then
    echo "FAIL: cannot export wrong-anchor public key"
    sed 's/^/  /' "$BACKUP_DIR/export-wrong.err" 2>/dev/null || true
    exit 1
  fi
  command -v ssh-keygen >/dev/null 2>&1 || { echo "FAIL: ssh-keygen not on PATH — SSH cases gate the format check and must never skip"; exit 1; }
  # SSH fixtures need git >= 2.34 (gpg.format=ssh signing; GIT_CONFIG_* also
  # needs >= 2.32, covered by the same floor). Hard FAIL, never skip: on an
  # older git the tag creation below would die opaquely, and an ignored
  # GIT_CONFIG_GLOBAL would let the allowedSigners cases pass vacuously.
  # (Compare parts, not a packed number: "%d%02d" formats 2.54 as 254 and
  # misfires the gate on every modern git.)
  GIT_VER="$(git --version | awk '{print $3}')"
  GIT_MAJOR="$(printf '%s' "$GIT_VER" | cut -d. -f1)"
  GIT_MINOR="$(printf '%s' "$GIT_VER" | cut -d. -f2)"
  if [ "$GIT_MAJOR" -gt 2 ] || { [ "$GIT_MAJOR" -eq 2 ] && [ "${GIT_MINOR:-0}" -ge 34 ]; }; then
    :
  else
    echo "FAIL: git $GIT_VER cannot sign with gpg.format=ssh and ignores GIT_CONFIG_GLOBAL (needs >= 2.34) — SSH cases gate the format check and must never skip"; exit 1
  fi
  if ! ssh-keygen -t ed25519 -N '' -C 'harness@local.invalid' -f "$BACKUP_DIR/ssh-key" </dev/null >"$BACKUP_DIR/ssh-keygen.log" 2>&1; then
    echo "FAIL: cannot generate ephemeral SSH key"
    sed 's/^/  /' "$BACKUP_DIR/ssh-keygen.log" 2>/dev/null || true
    exit 1
  fi
  # `*` principal: the harness only needs *some* verifiable trust for the
  # attacker config (a real attacker would name the victim's email).
  printf '%s %s\n' "*" "$(cut -d' ' -f1-2 "$BACKUP_DIR/ssh-key.pub")" > "$BACKUP_DIR/allowed-signers"
  printf '[gpg "ssh"]\n\tprogram = ssh-keygen\n\tallowedSignersFile = %s/allowed-signers\n' "$BACKUP_DIR" > "$BACKUP_DIR/attacker.gitconfig"
}
# Default-anchor fixtures for the production origin/main path: GOOD (tree
# carries the ephemeral PUBLIC key), NONE (keyless tree), BAD (garbage).
# Built with plumbing (mktree needs nested trees one level at a time —
# slash paths are rejected flat), descending from the seeded tip. No private
# keys involved — only the PUBLIC armor is embedded; the HEAD tag is still
# signed by the throwaway key. Bare main starts at GOOD; per-test rotation
# goes through reset_origin_main.
setup_anchor_fixtures() {
  SEED_TIP="$(git --git-dir="$TEST_ORIGIN" rev-parse --verify refs/heads/main)" || { echo "FAIL: cannot read throwaway origin main"; exit 1; }
  ANCHOR_GOOD_BLOB="$(git --git-dir="$TEST_ORIGIN" hash-object -w "$STAMP_SIGNING_KEY")" || { echo "FAIL: cannot hash ephemeral public key"; exit 1; }
  printf 'not a key at all\n' > "$BACKUP_DIR/garbage-key.txt"
  # BAD-anchor content is armor-header-first + garbage rest: it passes the
  # first-line armor contract and fails deterministically at gpg import
  # (covering the import-failure branch — a fully-garbage anchor would stop
  # one gate earlier at the armor check).
  printf '%s\n%s\n%s\n' "-----BEGIN PGP PUBLIC KEY BLOCK-----" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "(not a real key)" > "$BACKUP_DIR/bad-anchor-key.txt"
  ANCHOR_BAD_BLOB="$(git --git-dir="$TEST_ORIGIN" hash-object -w "$BACKUP_DIR/bad-anchor-key.txt")" || { echo "FAIL: cannot hash bad-anchor key"; exit 1; }
  # Binary export of the same key: gpg imports it fine standalone (proven in
  # isolation), so the harness refusal below pins the armor gate, not import.
  if ! gpg --batch --export harness@local.invalid > "$BACKUP_DIR/harness-signing.bin" 2>"$BACKUP_DIR/export-bin.err"; then
    echo "FAIL: cannot export binary throwaway public key"
    sed 's/^/  /' "$BACKUP_DIR/export-bin.err" 2>/dev/null || true
    exit 1
  fi
  # Deterministic non-armor key texts (no randomness, no NUL dependence):
  # garbage-key.txt (above) doubles as the plain non-armor STAMP fixture;
  # nonfirst-armor.txt embeds a valid marker past line one, pinning the
  # first-line-exact armor contract against a contains-check regression.
  printf 'junk line, not armor\n%s\n%s\n' "-----BEGIN PGP PUBLIC KEY BLOCK-----" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > "$BACKUP_DIR/nonfirst-armor.txt"
  ANCHOR_GOOD_SUB="$(printf '100644 blob %s\trelease-signing-key.pub\n' "$ANCHOR_GOOD_BLOB" | git --git-dir="$TEST_ORIGIN" mktree)" || { echo "FAIL: cannot build anchor subtree"; exit 1; }
  ANCHOR_GOOD_TREE="$(printf '040000 tree %s\t.github\n' "$ANCHOR_GOOD_SUB" | git --git-dir="$TEST_ORIGIN" mktree)" || { echo "FAIL: cannot build anchor tree"; exit 1; }
  ANCHOR_NONE_TREE="$(git --git-dir="$TEST_ORIGIN" mktree </dev/null)" || { echo "FAIL: cannot build keyless tree"; exit 1; }
  ANCHOR_BAD_SUB="$(printf '100644 blob %s\trelease-signing-key.pub\n' "$ANCHOR_BAD_BLOB" | git --git-dir="$TEST_ORIGIN" mktree)" || { echo "FAIL: cannot build garbage subtree"; exit 1; }
  ANCHOR_BAD_TREE="$(printf '040000 tree %s\t.github\n' "$ANCHOR_BAD_SUB" | git --git-dir="$TEST_ORIGIN" mktree)" || { echo "FAIL: cannot build garbage tree"; exit 1; }
  ANCHOR_GOOD="$(printf '%s\n' "synthetic anchor with ephemeral pub" | git --git-dir="$TEST_ORIGIN" -c user.name="stamp-test harness" -c user.email="harness@local.invalid" commit-tree "$ANCHOR_GOOD_TREE" -p "$SEED_TIP")" || { echo "FAIL: cannot commit good anchor"; exit 1; }
  ANCHOR_NONE="$(printf '%s\n' "synthetic anchor without key" | git --git-dir="$TEST_ORIGIN" -c user.name="stamp-test harness" -c user.email="harness@local.invalid" commit-tree "$ANCHOR_NONE_TREE" -p "$SEED_TIP")" || { echo "FAIL: cannot commit keyless anchor"; exit 1; }
  ANCHOR_BAD="$(printf '%s\n' "synthetic anchor with garbage key" | git --git-dir="$TEST_ORIGIN" -c user.name="stamp-test harness" -c user.email="harness@local.invalid" commit-tree "$ANCHOR_BAD_TREE" -p "$SEED_TIP")" || { echo "FAIL: cannot commit garbage anchor"; exit 1; }
  git --git-dir="$TEST_ORIGIN" update-ref refs/heads/main "$ANCHOR_GOOD" || { echo "FAIL: cannot point throwaway origin main"; exit 1; }
}
mktag() {
  # Never touch a pre-existing tag: devs reuse names like internal/v9.9.1,
  # and silently stamping (then deleting) a real tag would be destructive.
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite/delete a real tag (delete it yourself if it is scratch)"; exit 1
  fi
  # Throwaway key via explicit -c (never the developer's; gpg.format forced
  # to OpenPGP); tagger identity pinned for runners without user.name/email.
  git -c tag.gpgsign=false -c gpg.format=openpgp -c user.signingkey="$HARNESS_KEYID" \
    -c user.name="stamp-test harness" -c user.email="harness@local.invalid" \
    tag -s -m "harness $1" "$1" HEAD || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}
mktag_unsigned() {
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite it"; exit 1
  fi
  # Explicitly unsigned (gpgsign=false defeats a global tag.gpgsign=true;
  # forcesignannotated=false pins the annotated-but-unsigned shape).
  # Identity pinned like mktag.
  git -c tag.gpgsign=false -c tag.forcesignannotated=false \
    -c user.name="stamp-test harness" -c user.email="harness@local.invalid" \
    tag -a -m "harness unsigned $1" "$1" HEAD || { echo "FAIL: cannot create tag '$1'"; exit 1; }
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
  git -c tag.gpgsign=false -c gpg.format=openpgp -c user.signingkey="$HARNESS_KEYID" \
    -c user.name="stamp-test harness" -c user.email="harness@local.invalid" \
    tag -s -m "harness $1" "$1" "$2" || { echo "FAIL: cannot create tag '$1'"; exit 1; }
  CREATED_TAGS="$CREATED_TAGS $1"
}
mktag_ssh() { # mktag_ssh <tag> <message>: SSH-signed (non-OpenPGP) fixture
  if git rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then
    echo "FAIL: tag '$1' already exists locally — refusing to overwrite it"; exit 1
  fi
  # gpg.format=ssh + ephemeral key; </dev/null proves no signing prompt.
  git -c gpg.format=ssh -c user.signingkey="$BACKUP_DIR/ssh-key.pub" \
    -c user.name="stamp-test harness" -c user.email="harness@local.invalid" \
    tag -s -m "$2" "$1" HEAD </dev/null || { echo "FAIL: cannot create tag '$1'"; exit 1; }
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

# 4d. Cloud fail-closed guards: overrides never skip verification on Cloud,
# even set-but-empty (both sides presence-checked; fires pre-discovery).
expect 1 "override on Cloud refused" "local simulation only" \
  env CI_XCODE_CLOUD=1 TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=42 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "empty override on Cloud refused" "local simulation only" \
  env CI_XCODE_CLOUD=1 TAG_OVERRIDE="" CI_BUILD_NUMBER=42 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "override with empty Cloud marker refused" "local simulation only" \
  env CI_XCODE_CLOUD= TAG_OVERRIDE="internal/v9.9.7" CI_BUILD_NUMBER=42 CI_WORKFLOW="" sh "$SCRIPT"
expect 1 "empty override with empty Cloud marker refused" "local simulation only" \
  env CI_XCODE_CLOUD= TAG_OVERRIDE="" CI_BUILD_NUMBER=42 CI_WORKFLOW="" sh "$SCRIPT"

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
# SNAP_BEFORE pins stamped files: refusal must precede stamping, not follow.
SNAP_BEFORE="$(snapshot_files)"
mktag_unsigned internal/v9.9.0
expect 1 "unsigned tag refused" "does not carry an OpenPGP signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "unsigned refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5d. Lightweight tags are bare refs (no tag object, no signature) and must
# be refused like unsigned ones.
mktag_lightweight internal/v9.9.0
expect 1 "lightweight tag refused" "does not carry an OpenPGP signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "lightweight refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5e. Wrong-anchor refusal: tag signed by the throwaway key, verified
# against a SECOND ephemeral anchor (never unset — the premerge default
# anchor lacks the key file and would only prove the missing-key path).
setup_format_fixtures
setup_anchor_fixtures
mktag internal/v9.9.0
expect 1 "wrong-key tag refused" "no valid release signature" \
  env -u TAG_OVERRIDE STAMP_SIGNING_KEY="$BACKUP_DIR/wrong-anchor.pub" CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "wrong-key refusal stamps nothing"
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
# 5g. Cloud trust-anchor guard: a signed tag at HEAD verified against an
# alternate key (the harness's STAMP_SIGNING_KEY, still exported from
# setup_signing) must be refused on Cloud before any verification or
# stamping — the repo key is the sole Cloud anchor.
mktag internal/v9.9.0
expect 1 "alternate key on Cloud refused" "sole Cloud trust anchor" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" CI_XCODE_CLOUD=1 sh "$SCRIPT"
assert_unstamped "Cloud alternate-key refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.0
expect 1 "alternate key with empty Cloud marker refused" "sole Cloud trust anchor" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" CI_XCODE_CLOUD= sh "$SCRIPT"
assert_unstamped "Cloud empty-marker refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5h. SSH-signed tags are non-OpenPGP and must be refused at the format
# gate — even when the runner's git config would verify them (attacker
# allowedSigners trusting the ephemeral key): the gate inspects the tag
# object before any backend is invoked.
mktag_ssh internal/v9.9.0 "harness ssh internal/v9.9.0"
expect 1 "ssh-signed tag refused" "does not carry an OpenPGP signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "ssh refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag_ssh internal/v9.9.0 "harness ssh internal/v9.9.0"
expect 1 "ssh-signed tag refused despite allowedSigners" "does not carry an OpenPGP signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" GIT_CONFIG_GLOBAL="$BACKUP_DIR/attacker.gitconfig" GIT_CONFIG_SYSTEM=/dev/null sh "$SCRIPT"
assert_unstamped "ssh allowedSigners refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5i. Armor-spoof pin (LAST-BEGIN rule): a fake PGP BEGIN marker embedded in
# the annotation of an SSH-signed tag must NOT pass the format gate — the
# real (SSH) block is always appended last. Under the old anywhere-grep this
# tag verified cleanly via the attacker's allowedSigners and stamped.
SPOOF_MSG="$(printf '%s\n%s\n%s\n%s' "harness spoof internal/v9.9.0" "-----BEGIN PGP SIGNATURE-----" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "(not a real signature)")"
mktag_ssh internal/v9.9.0 "$SPOOF_MSG"
expect 1 "armor-spoof ssh tag refused" "does not carry an OpenPGP signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" GIT_CONFIG_GLOBAL="$BACKUP_DIR/attacker.gitconfig" GIT_CONFIG_SYSTEM=/dev/null sh "$SCRIPT"
assert_unstamped "armor-spoof refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5j. Default production anchor (origin/main): the hermetic main carries the
# ephemeral PUBLIC key (synthesized by setup_anchor_fixtures — no private
# keys, no waiting for a merge), so the absent-STAMP control verifies and
# stamps. Rotations + reset_origin_main pin the fail-closed branches with
# precise messages (merge-independent: the hermetic main is synthesized, so
# unlike the real origin these do not vary pre/post-merge). The SUCCESS case
# stamps, so the tracked trio is restored right after for later asserts.
reset_origin_main "$ANCHOR_GOOD"
mktag internal/v9.9.0
expect 0 "default anchor verifies and stamps" "Version unanimity OK: marketing=9.9.0 build=5 channel=internal" \
  env -u TAG_OVERRIDE -u STAMP_SIGNING_KEY CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
for f in $tracked; do cp "$BACKUP_DIR/$f" "$f"; done
# SUCCESS stamped: re-pin the baseline to the restored pristine files so the
# refusal asserts below compare against the true pre-stamp state.
SNAP_BEFORE="$(snapshot_files)"
reset_origin_main "$ANCHOR_NONE"
mktag internal/v9.9.0
expect 1 "missing origin/main anchor refused" "cannot read the release signing key from origin/main" \
  env -u TAG_OVERRIDE -u STAMP_SIGNING_KEY CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "missing-anchor refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
reset_origin_main "$ANCHOR_BAD"
mktag internal/v9.9.0
expect 1 "garbage origin/main anchor refused" "cannot import the release signing key" \
  env -u TAG_OVERRIDE -u STAMP_SIGNING_KEY CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "garbage-anchor refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# Anchor-selection refusals (fail before any read/verify/stamp).
mktag internal/v9.9.0
expect 1 "empty STAMP refused" "is set but empty" \
  env -u TAG_OVERRIDE STAMP_SIGNING_KEY= CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "empty-STAMP refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# Non-armor STAMP inputs stop at the explicit first-line armor contract
# (deterministic — never at import side effects): plain garbage, a valid
# marker past line one (pins first-line-exactness against a contains-check
# regression), and a binary export that gpg would import fine standalone.
mktag internal/v9.9.0
expect 1 "garbage STAMP refused" "is not ASCII-armored OpenPGP" \
  env -u TAG_OVERRIDE STAMP_SIGNING_KEY="$BACKUP_DIR/garbage-key.txt" CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "garbage-STAMP refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.0
expect 1 "non-first-line marker STAMP refused" "is not ASCII-armored OpenPGP" \
  env -u TAG_OVERRIDE STAMP_SIGNING_KEY="$BACKUP_DIR/nonfirst-armor.txt" CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "nonfirst-marker refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.0
expect 1 "binary STAMP refused" "is not ASCII-armored OpenPGP" \
  env -u TAG_OVERRIDE STAMP_SIGNING_KEY="$BACKUP_DIR/harness-signing.bin" CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "binary-STAMP refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
mktag internal/v9.9.0
expect 1 "missing anchor file refused" "release signing key not found" \
  env -u TAG_OVERRIDE STAMP_SIGNING_KEY="$BACKUP_DIR/does-not-exist.pub" CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "missing-file refusal stamps nothing"
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
# 5k. Symbolic tracking-ref safety: reset/fetch must never dereference a
# symref tracking ref into a caller referent (plain `update-ref -d` on a
# symref destroys its TARGET branch, and a fetch through it rewrites the
# referent). Fixture symrefs tracking to a scratch branch — guarded like
# tags (never overwrite a real branch; tracked for restore) — and the
# unsigned-tag run below exercises reset + the script fetch + refusal.
if git rev-parse -q --verify "refs/heads/stamp-test/sentinel" >/dev/null 2>&1; then
  echo "FAIL: branch 'stamp-test/sentinel' already exists locally — refusing to overwrite it"; exit 1
fi
git branch stamp-test/sentinel HEAD || { echo "FAIL: cannot create sentinel branch"; exit 1; }
CREATED_BRANCHES="$CREATED_BRANCHES stamp-test/sentinel"
git symbolic-ref refs/remotes/origin/main refs/heads/stamp-test/sentinel || { echo "FAIL: cannot symref tracking ref"; exit 1; }
SENTINEL_TIP="$(git rev-parse --verify refs/heads/stamp-test/sentinel)"
reset_origin_main "$ANCHOR_GOOD"
mktag_unsigned internal/v9.9.0
expect 1 "symref tracking: unsigned refused" "does not carry an OpenPGP signature" \
  env -u TAG_OVERRIDE CI_BUILD_NUMBER=5 CI_WORKFLOW="iOS Internal Release" sh "$SCRIPT"
assert_unstamped "symref refusal stamps nothing"
if [ "$(git rev-parse --verify refs/heads/stamp-test/sentinel)" != "$SENTINEL_TIP" ]; then
  echo "FAIL: symref tracking let a caller referent move"; FAIL=$((FAIL + 1))
else
  echo "ok: symref referent intact"; PASS=$((PASS + 1))
fi
for t in $CREATED_TAGS; do git tag -d "$t" >/dev/null 2>&1 || true; done; CREATED_TAGS=""
git branch -D stamp-test/sentinel >/dev/null 2>&1 || true; CREATED_BRANCHES=""

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
