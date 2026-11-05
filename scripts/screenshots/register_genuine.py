#!/usr/bin/env python3
"""Per-locale genuine LA registration after run_device_worker (local use).

For each locale cell: register staged genuine pixels (record-external-frame,
session-stub bindings; no observation gate — owner visual check governs)
then re-run finalize-run with provenance. Fail-fast NEVER: every cell/frame
records honestly and the run continues. LIFIO_CAPTURE_CI=1 bypass is used
(no approval files) and every manifest's ci_approval_bypass flag is
reported honestly.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAPTURE = HERE / "capture.py"

GEO = {"iphone69": (1320, 2868), "iphone63": (1206, 2622),
       "ipad13": (2064, 2752)}
LA_FRAMES = {"iphone69": ["la-lock", "la-compact", "la-expanded"],
             "iphone63": ["la-lock", "la-compact", "la-expanded"],
             "ipad13": ["la-lock"]}  # island N/A by design on iPad


def run_cap(args, logf, timeout=180):
    env = dict(os.environ)
    env["LIFIO_CAPTURE_LEASE"] = "1"  # harmless; record/finalize are local
    try:
        p = subprocess.run([sys.executable, str(CAPTURE)] + args,
                           capture_output=True, text=True, timeout=timeout,
                           env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        logf.write(f"LAUNCH-FAIL {args[0]}: {exc}\n")
        return None
    logf.write(f"$ capture.py {' '.join(args)}\nrc={p.returncode}\n"
               f"stdout={p.stdout[-800:]}\nstderr={p.stderr[-800:]}\n")
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device-key", required=True)
    ap.add_argument("--udid", required=True)
    ap.add_argument("--shots", required=True)
    ap.add_argument("--provenance", required=True)
    ap.add_argument("--locales", required=True,
                    help="JSON list, e.g. '[\"en\",\"ru\"]'")
    ap.add_argument("--log-dir", required=True)
    a = ap.parse_args()
    dev, udid = a.device_key, a.udid
    shots = Path(a.shots)
    logdir = Path(a.log_dir)
    locales = json.loads(a.locales)
    geo = GEO[dev]
    geostr = f"{geo[0]}x{geo[1]}"
    cells = {}
    for loc in locales:
        ldir = shots / dev / loc
        cell = {"device": dev, "locale": loc, "worker": "unknown",
                "genuine": {}, "finalize_rc": None,
                "manifest_status": None, "pending": None,
                "ci_approval_bypass": None, "notes": []}
        logpath = logdir / f"cell-{dev}-{loc}.json"
        try:
            with open(shots / dev / "worker-summary.json", encoding="utf-8") as fh:
                summ = json.load(fh)
            cell["worker"] = (summ.get("pairs", {}).get(loc, {}).get("r1"))
        except (OSError, ValueError):
            cell["notes"].append("worker-summary unreadable")
        logf = open(logdir / f"reg-{dev}-{loc}.log", "w",
                    encoding="utf-8")
        try:
            mans = sorted((ldir / "runs").glob("*/run-manifest.json")) \
                if (ldir / "runs").is_dir() else []
            if len(mans) != 1:
                cell["notes"].append(
                    f"run discovery: {len(mans)} manifests (want 1); "
                    "genuine registration skipped")
                continue
            run_dir = mans[0].parent
            rid = run_dir.name
            cell["run_id"] = rid
            pins = sorted((ldir / "requests").glob("*-pinned-totals.json")) \
                if (ldir / "requests").is_dir() else []
            if len(pins) != 1:
                cell["notes"].append(
                    f"pin discovery: {len(pins)} files; skipped")
                continue
            pin = str(pins[0])
            livep = run_dir / "staging" / "live-capture.json"
            live = None
            if livep.is_file():
                try:
                    live = json.loads(livep.read_text(encoding="utf-8"))
                except ValueError as exc:
                    cell["notes"].append(f"live-capture.json unreadable: {exc}")
            else:
                cell["notes"].append("staging/live-capture.json missing "
                                     "(realtime session never staged)")
            if dev == "ipad13":
                cell["notes"].append("island N/A by design (no island "
                                     "staging attempted)")
            for frame in LA_FRAMES[dev]:
                frec = {"attempted": False, "rc": None, "sha256": None,
                        "skipped": None}
                cell["genuine"][frame] = frec
                stubp = run_dir / "frames" / f"{frame}.json"
                if not stubp.is_file():
                    frec["skipped"] = "no trusted stub (session never ran frame)"
                    continue
                try:
                    stub = json.loads(stubp.read_text(encoding="utf-8"))
                except ValueError:
                    frec["skipped"] = "stub unreadable"
                    continue
                if stub.get("capture") == "external-lock-screen":
                    frec["skipped"] = "already genuine (rerun?)"
                    frec["sha256"] = stub.get("screenshot_sha256")
                    continue
                nonce, seq = stub.get("session_nonce"), stub.get("seq")
                statep = run_dir / "states" / f"session-{nonce}-{seq}-{frame}.ack.json"
                if not statep.is_file():
                    frec["skipped"] = f"per-frame ack missing: {statep.name}"
                    continue
                if live is None:
                    frec["skipped"] = "no live-capture record"
                    continue
                if frame == "la-lock":
                    png = run_dir / "staging" / "live-la-lock.png"
                    cap_at = (live.get("lock") or {}).get("captured_at_iso")
                    mask = "default"
                    dism = (live.get("consent_dismissal") or {}).get("outcome")
                    if dism and dism != "absent":
                        cell["notes"].append(f"lock consent_dismissal={dism} "
                                             "(pixels still genuine)")
                elif frame == "la-compact":
                    if not (live.get("compact") or {}).get("verdict", {}).get("live"):
                        frec["skipped"] = (
                            "compact verdict not live "
                            f"({(live.get('compact') or {}).get('verdict', {}).get('reason', '')}); "
                            "no island claim, stub stays pending")
                        continue
                    png = run_dir / "staging" / "live-la-compact.png"
                    cap_at = (live.get("compact") or {}).get("captured_at_iso")
                    mask = "black"
                else:  # la-expanded
                    exp = live.get("expanded")
                    if not isinstance(exp, dict) or "captured_at_iso" not in exp:
                        why = (live.get("expanded_attempt") or {}).get("reason", "no-card")
                        frec["skipped"] = f"no verified card ({why}); stays pending"
                        continue
                    png = run_dir / "staging" / "live-la-expanded.png"
                    cap_at = exp.get("captured_at_iso")
                    mask = "black"
                if not cap_at:
                    frec["skipped"] = "captured_at missing in live record"
                    continue
                if not png.is_file():
                    frec["skipped"] = f"staged PNG missing: {png.name}"
                    continue
                frec["attempted"] = True
                p = run_cap(["record-external-frame", "--out", str(ldir),
                             "--run-id", rid, "--frame", frame,
                             "--png", str(png), "--captured-at", cap_at,
                             "--state", str(statep), "--pinned-totals", pin,
                             "--geometry", geostr, "--device", udid,
                             "--mask", mask], logf)
                if p is None:
                    frec["rc"] = "launch-fail"
                    continue
                frec["rc"] = p.returncode
                if p.returncode == 0:
                    try:
                        rec = json.loads(p.stdout)
                        frec["sha256"] = rec.get("screenshot_sha256")
                    except ValueError:
                        pass
            # Re-finalize with provenance (flips pending->complete where genuine).
            p = run_cap(["finalize-run", "--out", str(ldir), "--run-id", rid,
                         "--provenance", a.provenance], logf)
            if p is None:
                cell["finalize_rc"] = "launch-fail"
                cell["notes"].append("finalize-run launch failed")
            else:
                cell["finalize_rc"] = p.returncode
                try:
                    man = json.loads(p.stdout)
                    cell["manifest_status"] = man.get("status")
                    cell["ci_approval_bypass"] = man.get("ci_approval_bypass")
                    frames = {r.get("frame"): r for r in man.get("frames", [])
                              if isinstance(r, dict)}
                    g = {f: (frames.get(f, {}).get("capture")) for f in LA_FRAMES[dev]}
                    cell["manifest_captures"] = g
                except ValueError:
                    cell["notes"].append("finalize stdout not JSON")
                try:
                    mf = json.loads((run_dir / "run-manifest.json").read_text(
                        encoding="utf-8"))
                    cell["pending"] = mf.get("pending") if isinstance(mf, dict) else None
                    if cell["manifest_status"] is None and isinstance(mf, dict):
                        cell["manifest_status"] = mf.get("status")
                    if cell["ci_approval_bypass"] is None and isinstance(mf, dict):
                        cell["ci_approval_bypass"] = mf.get("ci_approval_bypass")
                except (OSError, ValueError) as exc:
                    cell["notes"].append(f"run-manifest unreadable: {exc}")
        finally:
            logf.close()
            try:
                logpath.write_text(json.dumps(cell, indent=2, sort_keys=True) + "\n",
                                   encoding="utf-8")
            except OSError:
                pass
            cells[loc] = cell
            print(f"{dev}/{loc}: worker={cell['worker']} "
                  f"finalize_rc={cell['finalize_rc']} "
                  f"status={cell['manifest_status']} "
                  f"genuine={cell['genuine']} notes={cell['notes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
