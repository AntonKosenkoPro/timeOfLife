#!/bin/bash
# Local full-bundle driver: devices x locales, strictly sequential.
# Owned sims only (prefix local-bundle-); shared sims never touched.
# One owned simulator at a time: create -> boot -> install -> worker ->
# genuine registration -> shutdown -> delete, per device in order.
# Fail-fast NEVER: every step records status and continues.
# Outputs under $OUT_ROOT (default /tmp/lifio-bundle; never git).
# Usage: run_local_bundle.sh [--out DIR] [--devices k1,k2] [--locales JSON]
#        [--skip-build]   (reuses the previous build under OUT/dd)
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT=/tmp/lifio-bundle
DEVICES="iphone69,iphone63,ipad13"
LOCALES_JSON='["en","ru","zh-Hans","es-419","pt-BR"]'
SKIP_BUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_ROOT="$2"; shift 2;;
    --devices) DEVICES="$2"; shift 2;;
    --locales) LOCALES_JSON="$2"; shift 2;;
    --skip-build) SKIP_BUILD=1; shift 1;;
    *) echo "unknown flag $1 (see header)"; exit 2;;
  esac
done
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
  udid=$(xcrun simctl create "$name" "$dt" "$RT_ID" 2>"$LOGS/$key-create.log") \
    || { log "device $key: sim create FAILED, SKIP device"; return 0; }
  log "device $key: created $name $udid"
  echo "$udid" > "$OUT_ROOT/$key.udid"
  if [ "$udid" = "$SHARED_UDID" ]; then log "device $key: REFUSING shared UDID, abort device"; return 0; fi
  xcrun simctl boot "$udid" >>"$LOGS/$key-boot.log" 2>&1 \
    || { log "device $key: boot FAILED, delete+continue"; xcrun simctl delete "$udid" >/dev/null 2>&1; return 0; }
  xcrun simctl bootstatus "$udid" -b >>"$LOGS/$key-boot.log" 2>&1 \
    || log "device $key: bootstatus rc!=0 (continue)"
  xcrun simctl install "$udid" "$APP" >>"$LOGS/$key-install.log" 2>&1 \
    || { log "device $key: install FAILED, shutdown+delete+continue"; xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1; return 0; }
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
  xcrun simctl delete "$udid" >/dev/null 2>&1 || log "device $key: delete FAILED (manual cleanup needed: $udid)"
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
for d in $DEVICES; do run_device "$d"; done
IFS=$OLDIFS
stage_bezels
render_panels
log "=== bundle done ==="
