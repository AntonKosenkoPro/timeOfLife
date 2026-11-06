#!/bin/bash
# Local full-bundle driver: devices x locales (--jobs parallel capable).
# Owned sims only (prefix local-bundle-); shared sims never touched.
# One owned simulator at a time: create -> boot -> install -> worker ->
# genuine registration -> shutdown -> delete, per device in order.
# Fail-fast NEVER: every step records status and continues.
# Outputs under $OUT_ROOT (default /tmp/lifio-bundle; never git).
# Usage: run_local_bundle.sh [--out DIR] [--devices k1,k2] [--locales JSON]
#        [--skip-build]   (reuses the previous build under OUT/dd)
#        [--jobs N]       (1..5 parallel devices; default 5. Leases are
#        per-device and argent multiplexes across sims; keep 1 on small
#        hosts, as parallel sims share CPU/RAM and timing-sensitive holds
#        may flake under load.)
#        [--keep-sims]    (reuse owned local-bundle-* sims across runs:
#        erase + reboot instead of create/delete. Erase restores clean
#        state so the consent prompt resurfaces; shared/preinstalled sims
#        are never touched either way.)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT=/tmp/lifio-bundle
DEVICES="iphone69,iphone63,ipad13"
LOCALES_JSON='["en","ru","zh-Hans","es-419","pt-BR"]'
SKIP_BUILD=0
JOBS=5
KEEP_SIMS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_ROOT="$2"; shift 2;;
    --devices) DEVICES="$2"; shift 2;;
    --locales) LOCALES_JSON="$2"; shift 2;;
    --skip-build) SKIP_BUILD=1; shift 1;;
    --jobs) JOBS="$2"; shift 2;;
    --keep-sims) KEEP_SIMS=1; shift 1;;
    *) echo "unknown flag $1 (see header)"; exit 2;;
  esac
done
case "$JOBS" in
  1|2|3|4|5) ;;
  *) echo "--jobs N must be 1..5"; exit 2;;
esac
SHOTS=$OUT_ROOT/shots
LOGS=$OUT_ROOT/logs
DD=$OUT_ROOT/dd
BEZELS=$OUT_ROOT/bezels
PANELS=$OUT_ROOT/panels
RT_ID=com.apple.CoreSimulator.SimRuntime.iOS-27-0
APP=$DD/Build/Products/Screenshot-iphonesimulator/TimeOfLife.app
PROV=$OUT_ROOT/capture-provenance.json
CAPTIONS=$REPO/openspec/changes/archive/2026-11-03-app-store-screenshot-pilot/captions
mkdir -p "$SHOTS" "$LOGS" "$BEZELS" "$PANELS"
export LIFIO_CAPTURE_LEASE=1
export LIFIO_CAPTURE_CI=1  # logged honestly per manifest; never approval
SHARED_UDID=C18365F5-AE32-47DE-9744-324605B0506E

log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$OUT_ROOT/timing.log"; }

devtype_for() {
  case "$1" in
    iphone69) echo com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max;;
    iphone63) echo com.apple.CoreSimulator.SimDeviceType.iPhone-17;;
    ipad13)   echo com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB;;
    *) echo "UNKNOWN-DEVICE-$1"; return 1;;
  esac
}

verify_devtypes() {
  python3 - "$@" <<'PY'
import json, subprocess, sys
want = {"iphone69": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max",
        "iphone63": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
        "ipad13": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"}
raw = subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"], text=True)
ids = {d["identifier"] for d in json.loads(raw).get("devicetypes", [])}
bad = [k for k, v in want.items() if v not in ids]
if bad:
    print(f"FAIL-CLOSED devtype mismatch: {bad}", file=sys.stderr)
    sys.exit(2)
print("devtypes verified")
PY
}

build_app() {
  log "build start"
  (cd "$REPO/ios/TimeOfLife" && xcodegen generate >>"$LOGS/build.log" 2>&1 \
    && xcodebuild build -scheme TimeOfLife -configuration Screenshot \
    -destination "generic/platform=iOS Simulator" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "$DD" >>"$LOGS/build.log" 2>&1) \
    || { log "build FAILED, abort bundle"; exit 2; }
  # One xcodebuild at a time (DerivedData lock); warning-clean build.
  [ -d "$APP" ] || { log "built app missing at $APP, abort bundle"; exit 2; }
  log "build ok"
  git -C "$REPO" rev-parse HEAD > "$OUT_ROOT/commit.txt" 2>/dev/null || true
  python3 -c "import json; json.dump({'commit_base': open('$OUT_ROOT/commit.txt').read().strip() if __import__('os').path.exists('$OUT_ROOT/commit.txt') else 'unknown', 'dirty': False}, open('$PROV','w'))"
}

run_device() {
  key=$1
  log "=== device $key start ==="
  dt=$(devtype_for "$key") || { log "device $key: unknown key, SKIP"; return 0; }
  name="local-bundle-$key"
  udid=""
  created_here=0
  if [ "$KEEP_SIMS" = 1 ]; then
    udid=$(xcrun simctl list devices -j 2>/dev/null | python3 -c "
import json, sys
want = '$name'
hits = [e['udid'] for b in json.load(sys.stdin)['devices'].values() for e in b if e.get('name') == want and e.get('udid')]
print(hits[0] if len(hits) == 1 else '')")
    if [ -n "$udid" ]; then
      log "device $key: reusing owned sim $udid (erase+reboot)"
      xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
      xcrun simctl erase "$udid" >>"$LOGS/$key-boot.log" 2>&1 \
        || { log "device $key: erase FAILED, falling back to create"; udid=""; }
    fi
  fi
  if [ -z "$udid" ]; then
    udid=$(xcrun simctl create "$name" "$dt" "$RT_ID" 2>"$LOGS/$key-create.log") \
      || { log "device $key: sim create FAILED, SKIP device"; return 0; }
    created_here=1
  fi
  log "device $key: created $name $udid"
  echo "$udid" > "$OUT_ROOT/$key.udid"
  if [ "$udid" = "$SHARED_UDID" ]; then log "device $key: REFUSING shared UDID, abort device"; return 0; fi
  # Boot THROUGH argent (not simctl): argent applies pre-boot
  # accessibility settings at boot, without which describe reads come
  # back empty and consent can never grant (proven: argent-booted sims
  # return full AX trees incl. system sheets; simctl-booted sims warn
  # that pre-boot settings were never applied). Headless: no GUI window.
  argent run boot-device --udid "$udid" --headless >>"$LOGS/$key-boot.log" 2>&1 \
    || { log "device $key: argent boot FAILED, delete+continue"; xcrun simctl delete "$udid" >/dev/null 2>&1; return 0; }
  xcrun simctl bootstatus "$udid" -b >>"$LOGS/$key-boot.log" 2>&1 \
    || log "device $key: bootstatus rc!=0 (continue)"
  xcrun simctl install "$udid" "$APP" >>"$LOGS/$key-install.log" 2>&1 \
    || { log "device $key: install FAILED, shutdown+delete+continue"; xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1; return 0; }
  log "device $key: installed, warming argent transport"
  # Host-level cold start (tool-server spawn + ax-service attach) costs
  # tens of seconds on a busy host and must never burn hold budget:
  # one sacrificial describe here (best effort, generous timeout),
  # so in-session describes start warm. Failure is logged, never fatal.
  # (No `timeout(1)` on macOS — bound via python stdlib instead.)
  python3 -c "import subprocess,sys; subprocess.run(['argent','run','describe','--udid','$udid'], timeout=120)" \
    >"$LOGS/$key-warmup.log" 2>&1 \
    || log "device $key: transport warm-up rc!=0 (sessions still try; see $key-warmup.log)"
  log "device $key: installed, worker start"
  set +e
  python3 "$REPO/scripts/screenshots/run_device_worker.py" \
    --device-key "$key" --device "$udid" --locales "$LOCALES_JSON" \
    --out "$SHOTS" --provenance "$PROV" >"$LOGS/$key-worker.log" 2>&1
  wrc=$?
  set -e
  log "device $key: worker rc=$wrc"
  set +e
  python3 "$REPO/scripts/screenshots/register_genuine.py" --device-key "$key" \
    --udid "$udid" --shots "$SHOTS" --provenance "$PROV" \
    --locales "$LOCALES_JSON" --log-dir "$LOGS" >"$LOGS/$key-genuine.log" 2>&1
  grc=$?
  set -e
  log "device $key: genuine rc=$grc"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  if [ "$created_here" = 1 ] && [ "$KEEP_SIMS" != 1 ]; then
    xcrun simctl delete "$udid" >/dev/null 2>&1 || log "device $key: delete FAILED (manual cleanup needed: $udid)"
  fi
  log "=== device $key done (worker=$wrc genuine=$grc) ==="
}

stage_bezels() {
  # Private release via local gh auth (value never read/copied); exact
  # manifest-hash verification precedes any use; no PNG enters git.
  dl="$OUT_ROOT/bezel-dl"
  mkdir -p "$dl"
  gh release download apple-bezels-v2 --repo AntonKosenkoPro/lifio-design-assets \
    --dir "$dl" >>"$LOGS/bezels.log" 2>&1 \
    || { log "bezel download FAILED (see bezels.log)"; return 0; }
  python3 "$REPO/scripts/panels/stage_bezel_assets.py" --source-dir "$dl" \
    --out "$BEZELS" --manifest "$dl/apple-bezels-manifest.json" \
    >>"$LOGS/bezels.log" 2>&1 \
    || log "bezel staging FAILED (panels will block honestly)"
}

render_panels() {
  devs=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1].split(',')))" "$DEVICES")
  python3 "$REPO/scripts/panels/panels.py" --render-matrix \
    --shots-dir "$SHOTS" --bezels-dir "$BEZELS" --out "$PANELS" \
    --captions-dir "$CAPTIONS" --devices "$devs" --languages "$LOCALES_JSON" \
    >>"$LOGS/panels.log" 2>&1 \
    || log "panels rc!=0 (blocked cells stay blocked, never fabricated)"
  python3 -c "import json; m=json.load(open('$PANELS/matrix-manifest.json')); print(m['counts'], m['status'])" 2>&1 | tee -a "$OUT_ROOT/timing.log"
}

cd "$REPO"
verify_devtypes || { log "devtype gate FAILED, abort bundle"; exit 2; }
command -v argent >/dev/null 2>&1 || log "WARNING: argent CLI missing on PATH — consent grant records failed-blocker, LA stays pending"
command -v gh >/dev/null 2>&1 || log "WARNING: gh CLI missing — bezel download skipped"
[ "$SKIP_BUILD" = 1 ] || build_app
[ -d "$APP" ] || { log "built app missing at $APP, abort bundle"; exit 2; }
OLDIFS=$IFS; IFS=,
# shellcheck disable=SC2162
if [ "$JOBS" = 1 ]; then
  for d in $DEVICES; do run_device "$d"; done
else
  log "parallel mode: up to $JOBS devices at once (leases per-device)"
  for d in $DEVICES; do
    run_device "$d" &
    while [ "$(jobs -pr | wc -l)" -ge "$JOBS" ]; do sleep 5; done
  done
  wait
fi
IFS=$OLDIFS
stage_bezels
render_panels
log "=== bundle done ==="
