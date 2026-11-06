#!/usr/bin/env python3
"""Live-capture hold-open tests (executor.run_session hold-open realtime).

Genuine Lock Screen / Dynamic Island pixels captured inside the realtime
session while it stays RUNNING: describe-backed consent-grant loop
(Allow/Always Allow centers from `argent run describe` only, never
blind), powerx2 lock + simctl screenshot with retry, compact re-probe with
pixel-verified pill. Fake HID backend + scripted simctl; no device, tmp only.

Red-to-green contract (Phase 1): hold-open lifecycle, lock-capture happy
path, consent-gate (no pill => no island claim), cleanup-while-locked.
"""

import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import executor as ex
import request_schema as rs
from test_session_run import (
    IPHONE63_MODEL,
    LA_BLOCK,
    PINNED,
    SessionFakeSimctl,
    base_request,
)

GEO63 = (1206, 2622)
NONCE_LIVE = "9" * 32

# Island region pinned from live headless pixels (locked1.png, 1206x2622):
# idle pill spans x[415,790] y[42,151]; the verdict box below adds margin.
PILL_BOX = (415, 790, 42, 151)


def _write_rgba_png(path: Path, width: int, height: int, fn) -> None:
    """Minimal valid RGBA PNG (stdlib only). fn(x, y) -> (r, g, b)."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            r, g, b = fn(x, y)
            raw += bytes((r, g, b, 255))

    def chunk(typ: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + typ + payload
                + struct.pack(">I", zlib.crc32(typ + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(bytes(raw)))
                     + chunk(b"IEND", b""))


def paint_plain(path: Path, seed: int = 0) -> None:
    """Wallpaper-like gradient, no pill mass (dark-free, dim)."""
    w, h = GEO63
    _write_rgba_png(path, w, h,
                    lambda x, y: (40 + ((x + y + seed) % 60),
                                  36 + ((x + seed) % 50),
                                  34 + ((y + seed) % 44)))


def paint_idle_pill(path: Path) -> None:
    """Gradient + pure-black idle pill (no live content)."""
    x0, x1, y0, y1 = PILL_BOX
    _write_rgba_png(path, *GEO63,
                    lambda x, y: (0, 0, 0) if (x0 <= x <= x1 and y0 <= y <= y1)
                    else (40 + (x % 60), 36 + (x % 50), 34 + (y % 44)))


def paint_live_pill(path: Path) -> None:
    """Idle pill + bright live content dots inside (timer/icon stand-in)."""
    x0, x1, y0, y1 = PILL_BOX
    dots = {(x, y) for x in range(x0 + 20, x1 - 20, 7)
            for y in range(y0 + 20, y1 - 20, 7)}

    def fn(x, y):
        if (x, y) in dots:
            return (255, 255, 255)
        if x0 <= x <= x1 and y0 <= y <= y1:
            return (0, 0, 0)
        return (40 + (x % 60), 36 + (x % 50), 34 + (y % 44))

    _write_rgba_png(path, *GEO63, fn)


# Expanded-card band mirror for GEO63 (executor.EXPANDED_REGIONS): a genuine
# long-press card renders here as a large dark mass with bright content.
CARD_BOX = (320, 886, 180, 594)


def paint_expanded_card(path: Path) -> None:
    """Live pill + dark expanded card with bright content below the island."""
    px0, px1, py0, py1 = PILL_BOX
    cx0, cx1, cy0, cy1 = CARD_BOX
    dots = {(x, y) for x in range(px0 + 20, px1 - 20, 7)
            for y in range(py0 + 20, py1 - 20, 7)}
    card_dots = {(x, y) for x in range(cx0 + 15, cx1 - 15, 9)
                 for y in range(cy0 + 15, cy1 - 15, 9)}

    def fn(x, y):
        if (x, y) in dots or (x, y) in card_dots:
            return (255, 255, 255)
        if px0 <= x <= px1 and py0 <= y <= py1:
            return (0, 0, 0)
        if cx0 <= x <= cx1 and cy0 <= y <= cy1:
            return (0, 0, 0)
        return (40 + (x % 60), 36 + (x % 50), 34 + (y % 44))

    _write_rgba_png(path, *GEO63, fn)


def paint_app_screen(path: Path) -> None:
    """Tap-opened-app stand-in: uniform near-white app chrome, no pill."""
    _write_rgba_png(path, *GEO63, lambda x, y: (235, 235, 235))


# Consent-sheet stand-in for GEO63: light alert body in the sheet band with
# a blue Allow-label block in its bottom half. Centroid is image-derived in
# the test via executor.find_allow_centroid (never a literal tap target).
SHEET_RECT = (253, 953, 1000, 1400)
SHEET_LABEL = (500, 700, 1280, 1320)


def paint_sheet(path: Path) -> None:
    """Wallpaper + light alert body + blue Allow label cluster."""
    sx0, sx1, sy0, sy1 = SHEET_RECT
    lx0, lx1, ly0, ly1 = SHEET_LABEL

    def fn(x, y):
        if lx0 <= x <= lx1 and ly0 <= y <= ly1:
            return (0, 122, 255)
        if sx0 <= x <= sx1 and sy0 <= y <= sy1:
            return (250, 250, 250)
        return (40 + (x % 60), 36 + (x % 50), 34 + (y % 44))

    _write_rgba_png(path, *GEO63, fn)


def paint_lock_banner(path: Path) -> None:
    """Wallpaper + red stop-button disc in the lock banner band
    (relative rows 0.662H-0.697H, geometry-relative like the verdict)."""
    w, h = GEO63
    y0, y1 = int(0.662 * h), int(0.697 * h)
    cy = (y0 + y1) // 2

    def fn(x, y):
        if (x - 300) ** 2 + (y - cy) ** 2 <= 40 ** 2:
            return (255, 60, 60)
        return (40 + (x % 60), 36 + (x % 50), 34 + (y % 44))

    _write_rgba_png(path, w, h, fn)


class FakeHidBackend(ex.HidBackend):
    """Scripted HID: legacy ax tree, scripted describe docs, or absent.

    ax: legacy dict prompt tree | None (ax_dump returns None: no prompt).
    ax_script: ordered describe-derived documents, one per ax_dump call;
      the last repeats (a persisting sheet keeps describing present). A
      script entry may be an Exception: ax_dump raises it (describe
      transport/parse failure model). Records calls.
    """

    def __init__(self, ax="absent", ax_script=None, tick=None,
                 timeout_s=30.0):
        self.calls: list = []
        self._ax = {"label": "root", "children": []} if ax == "absent" else ax
        self._script = list(ax_script) if ax_script is not None else None
        self._tick = tick
        self._timeout_s = timeout_s
        self.locked = False

    def press_button(self, button):
        self.calls.append(("button", button))
        if button.lower() == "power":
            self.locked = True

    def tap(self, x, y):
        self.calls.append(("tap", x, y))

    def multitouch_hold(self, x1, y1, x2, y2):
        self.calls.append(("hold", x1, y1, x2, y2))

    def long_press(self, x, y, duration_ms=1200):
        self.calls.append(("long-press", x, y, duration_ms))

    def ax_dump(self):
        self.calls.append(("ax",))
        if self._script is not None:
            doc = self._script[0]
            if len(self._script) > 1:
                self._script.pop(0)
            if isinstance(doc, Exception):
                if self._tick is not None:
                    try:
                        self._tick(float(self._timeout_s))
                    except Exception:
                        pass
                raise doc
            return doc
        return self._ax


def _desc_doc(*items):
    """Describe-derived document: items are (label, x, y) tap centers."""
    buttons = []
    for label, x, y in items:
        w, h = 0.134, 0.042
        buttons.append({"role": "AXButton", "label": label,
                        "center": [x, y],
                        "frame": [x - w / 2, y - h / 2, w, h]})
    return {"source": "ax-service", "buttons": buttons}


EMPTY_DOC = {"source": "ax-service", "buttons": []}

# Scratch-sim proven sheet centers (compact Allow, follow-up Always Allow).
ALLOW_XY = (0.717, 0.811)
ALWAYS_XY = (0.7235, 0.82)


ALLOW_TREE = {"label": "root", "children": [
    {"label": "Allow", "x": 0.5, "y": 0.9},
    {"label": "Deny", "x": 0.5, "y": 0.95},
]}


class LiveFakeSimctl(SessionFakeSimctl):
    """Session fake with scripted simctl-io screenshots (paint/raise queue)."""

    def __init__(self, container, io_script=None, **kw):
        kw.setdefault("list_model", IPHONE63_MODEL)
        kw.setdefault("png_size", GEO63)
        super().__init__(container, **kw)
        self.io_script = list(io_script or [])
        self.io_calls: list = []

    def __call__(self, argv):
        if len(argv) > 2 and argv[2] == "io":
            self.io_calls.append(list(argv))
            dest = Path(argv[-1])
            dest.parent.mkdir(parents=True, exist_ok=True)
            if self.io_script:
                action = self.io_script.pop(0)
                if action[0] == "raise":
                    raise action[1]
                action[1](dest)
            else:
                paint_plain(dest)
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        return super().__call__(argv)


def live_run(tmp: str, hid, io_script, run_id="live-r1", **kw):
    """Full realtime hold-open session on fakes (iphone63)."""
    udid = f"UDID-live-{os.getpid()}-{len(os.listdir(tmp))}"
    container = Path(tmp) / "container"
    container.mkdir(exist_ok=True)
    fake_kw = dict(la_block=dict(LA_BLOCK))
    fake_kw.update(kw.pop("fake_kw", {}))
    fake = LiveFakeSimctl(container, io_script=io_script, **fake_kw)
    run_dir = Path(tmp) / "runs" / run_id
    summary = ex.run_session(
        fake, udid, base_request(run_id), "realtime", run_dir,
        device_key="iphone63", pinned_totals=dict(PINNED), geometry=GEO63,
        session_nonce=kw.pop("session_nonce", NONCE_LIVE),
        hold_open=True, hid=hid,
        hold_timeout_s=kw.pop("hold_timeout_s", 60.0),
        interval_s=0.0, sleeper=ex.no_sleep, on_poll=fake.pump, **kw)
    return fake, hid, run_dir, summary, udid


def live_capture_record(run_dir: Path) -> dict:
    return json.loads((run_dir / "staging" / "live-capture.json")
                      .read_text(encoding="utf-8"))


def hold_script(compact_painter, lock_painter=None, expanded_painter=None):
    """Full io queue: 3 stock + 1 compact + 3 expanded + 1 probe + 2 lock.

    Slot counts match maximum consumption (expanded retries verdict-gated
    up to 3): no silent plain fallback inside the hold window. Card tests
    pass on the first attempt; the extra expanded slots read plain
    (honest no-card) unless the caller inlines card paints there."""
    lock_painter = lock_painter or paint_lock_banner
    expanded_painter = expanded_painter or paint_plain
    return ([("paint", paint_plain)] * 3
            + [("paint", compact_painter)]
            + [("paint", expanded_painter)]
            + [("paint", paint_plain)] * 2
            + [("paint", paint_plain)]
            + [("paint", lock_painter)] * 2)


class HoldOpenLifecycleTests(unittest.TestCase):
    def test_hold_open_rejected_for_pinned(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-holdpin-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = LiveFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "live-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("live-r1"), "pinned", run_dir,
                    device_key="iphone69", pinned_totals=dict(PINNED),
                    geometry=(1320, 2868), hold_open=True,
                    hid=FakeHidBackend(), sleeper=ex.no_sleep,
                    on_poll=fake.pump)
            self.assertIn("realtime-only", str(ctx.exception))

    def test_hold_open_requires_hid_backend(self):
        with tempfile.TemporaryDirectory() as tmp:
            udid = f"UDID-holdnohid-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = LiveFakeSimctl(container)
            run_dir = Path(tmp) / "runs" / "live-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("live-r1"), "realtime", run_dir,
                    device_key="iphone63", pinned_totals=dict(PINNED),
                    geometry=GEO63, hold_open=True, hid=None,
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("HID backend", str(ctx.exception))
            # No lease taken, no device touched on arg rejection.
            self.assertFalse(list(fake.io_calls))

    def test_hold_open_completes_with_verified_anchor(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            fake, hid, run_dir, summary, udid = live_run(
                tmp, hid, hold_script(paint_live_pill), run_id="live-r1")
            self.assertEqual(summary["status"], "complete")
            # Consent probed first, then Home, then powerx2 (spike pattern).
            kinds = [c[0] for c in hid.calls]
            self.assertEqual(kinds[0], "ax")
            self.assertIn(("button", "Home"), hid.calls)
            powers = [c for c in hid.calls if c == ("button", "Power")]
            self.assertEqual(len(powers), 2)
            self.assertLess(hid.calls.index(("button", "Home")),
                            hid.calls.index(("button", "Power")))
            # Anchor verified and bound on the live record.
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["anchor"], LA_BLOCK["activity_id"])
            self.assertEqual(
                rec["lock"]["capture_window"]["started_at"],
                LA_BLOCK["started_at"])
            self.assertTrue(rec["lock"]["captured_at_iso"])
            # Genuine pixels staged; the stub stays honestly pending
            # (genuine registration happens later, never OCR).
            lock_stub = json.loads(
                (run_dir / "frames" / "la-lock.json").read_text(
                    encoding="utf-8"))
            self.assertEqual(lock_stub["capture"],
                             "external-lock-screen-pending")
            self.assertNotIn("capture_window", lock_stub)
            receipt = json.loads(
                (run_dir / "sessions" / f"{NONCE_LIVE}.receipt.json")
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "complete")
            self.assertTrue(receipt["runner_verified"]["lease_released"])

    def test_per_frame_ack_archived_for_genuine_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            fake, hid, run_dir, summary, udid = live_run(
                tmp, hid, hold_script(paint_live_pill), run_id="live-r1")
            self.assertEqual(summary["status"], "complete")
            # The device state file is last-wins: without this archive only
            # the final seq-2 state survives and earlier frames fail closed
            # as stale acks at record-external-frame time.
            for seq, frame in enumerate(
                    ["la-lock", "la-compact", "la-expanded"]):
                ack_path = (run_dir / "states" /
                            f"session-{NONCE_LIVE}-{seq}-{frame}.ack.json")
                self.assertTrue(ack_path.is_file(),
                                f"missing per-frame ack {ack_path.name}")
                ack = json.loads(ack_path.read_text(encoding="utf-8"))
                self.assertEqual(ack["session_nonce"], NONCE_LIVE)
                self.assertEqual(ack["seq"], seq)
                self.assertEqual(ack["frame"], frame)
                self.assertEqual(ack["status"], "ready")

    def test_hold_requires_anchor(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            udid = f"UDID-noanchor-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = LiveFakeSimctl(container, la_block=None)
            run_dir = Path(tmp) / "runs" / "live-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("live-r1"), "realtime", run_dir,
                    device_key="iphone63", pinned_totals=dict(PINNED),
                    geometry=GEO63, session_nonce="8" * 32,
                    hold_open=True, hid=hid, interval_s=0.0,
                    sleeper=ex.no_sleep, on_poll=fake.pump)
            # An anchorless session contaminates at ack validation, before
            # any hold or HID input: no capture without a verified anchor.
            self.assertIn("contaminated", str(ctx.exception))
            self.assertEqual(hid.calls, [])

    def test_hold_timeout_contaminates_but_still_cleans_up(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = hold_script(paint_live_pill)
            udid = f"UDID-holdto-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = LiveFakeSimctl(container, io_script=script,
                                  la_block=dict(LA_BLOCK))
            run_dir = Path(tmp) / "runs" / "live-r1"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("live-r1"), "realtime", run_dir,
                    device_key="iphone63", pinned_totals=dict(PINNED),
                    geometry=GEO63, session_nonce="7" * 32,
                    hold_open=True, hid=hid, hold_timeout_s=0.0,
                    interval_s=0.0, sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("hold-open window expired", str(ctx.exception))
            receipt = json.loads(
                (run_dir / "sessions" / ("7" * 32 + ".receipt.json"))
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertTrue(receipt["runner_verified"]["chrome_restored"])
            self.assertTrue(
                receipt["runner_verified"]["process_terminated"])
            self.assertTrue(receipt["runner_verified"]["lease_released"])
            # Cleanup was still attempted (fail-closed, lease reusable).
            self.assertTrue(any(
                "SCREENSHOT_CLEANUP=" in " ".join(c)
                for c in fake.launches()))


class LockCaptureTests(unittest.TestCase):
    def test_lock_capture_happy_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill, paint_lock_banner),
                run_id="live-lock-1")
            self.assertEqual(summary["status"], "complete")
            lock_png = run_dir / "staging" / "live-la-lock.png"
            self.assertTrue(lock_png.is_file())
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["lock"]["screenshot_sha256"],
                             __import__("inspection").sha256_file(
                                 str(lock_png)))
            # Live pill + banner pixels confirm the pixels are real.
            self.assertTrue(rec["consent"]["confirmed"])
            dims = __import__("inspection").png_dimensions(str(lock_png))
            self.assertEqual(dims, GEO63)

    def test_lock_screenshot_retries_after_hid_transition(self):
        # First lock attempt drops (post-HID spawn flake, spike-proven);
        # bounded retry still lands settled pixels, session stays complete.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_plain)]
                      + [("raise", subprocess.TimeoutExpired("simctl", 60))]
                      + [("paint", paint_lock_banner)] * 2)
            fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-lock-2")
            self.assertEqual(summary["status"], "complete")
            # 3 stock + 1 compact (live first try) + 3 expanded (no card,
            # verdict-gated) + 1 dismissal probe (absent) + 1 dropped
            # + 2 lock.
            self.assertEqual(len(fake.io_calls), 3 + 1 + 3 + 1 + 1 + 2)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_lock_blank_banner_records_attempt_never_genuine(self):
        # Dead lock shot: banner-less pixels are attempt evidence only.
        # No live-la-lock.png is staged and the stub stays pending.
        # Confirmation semantics: only full-grant UI (verified banner or
        # genuine card) confirms — a live pill alone is provisional and
        # confirms nothing, so this record stays unconfirmed.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill, paint_plain),
                run_id="live-lock-blank")
            self.assertEqual(summary["status"], "complete")
            staging = run_dir / "staging"
            self.assertFalse((staging / "live-la-lock.png").is_file())
            self.assertTrue(
                (staging / "live-la-lock.attempt.png").is_file())
            rec = live_capture_record(run_dir)
            self.assertEqual(
                (rec.get("lock_attempt") or {}).get("outcome"), "no-banner")
            stub = json.loads(
                (run_dir / "frames" / "la-lock.json").read_text(
                    encoding="utf-8"))
            self.assertEqual(stub["capture"],
                             "external-lock-screen-pending")
            self.assertNotIn("capture_window", stub)
            # Live pill alone is provisional: without a verified banner
            # or genuine card this record stays unconfirmed.
            self.assertFalse(rec["consent"]["confirmed"])

    def test_confirmed_false_without_any_live_pixels(self):
        # No pill, no banner, no grant: nothing confirms anything.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_plain, paint_plain),
                run_id="live-lock-dark")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            self.assertFalse(rec["consent"]["confirmed"])
            self.assertEqual(
                (rec.get("lock_attempt") or {}).get("outcome"), "no-banner")

    def test_lock_banner_verdict_units(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "banner.png"
            paint_lock_banner(good)
            verdict = ex.lock_banner_verdict(str(good), GEO63)
            self.assertTrue(verdict["banner"])
            self.assertEqual(verdict["presentation"], "full")
            self.assertGreaterEqual(verdict["red_frac"], 0.002)
            blank = Path(tmp) / "blank.png"
            paint_plain(blank)
            verdict = ex.lock_banner_verdict(str(blank), GEO63)
            self.assertFalse(verdict["banner"])
            self.assertEqual(verdict["presentation"], "absent")
            self.assertEqual(verdict["red_frac"], 0.0)

    def test_lock_provisional_banner_stays_pending(self):
        # Slim pre-grant banner (small bottom banner, no full
        # presentation): provisional, never staged genuine.
        with tempfile.TemporaryDirectory() as tmp:
            w, h = GEO63
            cy = int(0.775 * h)

            def slim(path: Path) -> None:
                def fn(x, y):
                    if (x - 1000) ** 2 + (y - cy) ** 2 <= 35 ** 2:
                        return (255, 60, 60)
                    return (40 + (x % 60), 36 + (x % 50), 34 + (y % 44))

                _write_rgba_png(path, w, h, fn)

            probe = Path(tmp) / "slim.png"
            slim(probe)
            verdict = ex.lock_banner_verdict(str(probe), GEO63)
            self.assertFalse(verdict["banner"])
            self.assertEqual(verdict["presentation"], "provisional")

    def test_lock_promotion_stages_banner_after_grant(self):
        # Granted but banner not yet promoted (blank first exports):
        # unlock-relock forces SpringBoard re-evaluation, re-shoots
        # stage the full banner. Only fires when taps non-empty.
        with tempfile.TemporaryDirectory() as tmp:
            docs = [EMPTY_DOC] + [EMPTY_DOC] * (1 + ex.SHEET_WAIT_ROUNDS) + [
                    _desc_doc(("Allow", *ALLOW_XY)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_plain)]
                      + [("paint", paint_plain)] * 2
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-lock-promotion")
            self.assertEqual(summary["status"], "complete")
            # 3 stock + 1 compact + 3 expanded + 1 probe + 2 lock
            # + 1 promotion capture (breaks on first full banner).
            self.assertEqual(len(_fake.io_calls), 3 + 1 + 3 + 1 + 2 + 1)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())
            rec = live_capture_record(run_dir)
            self.assertIsNone(rec.get("lock_attempt"))
            promo = rec.get("lock_promotion") or {}
            self.assertTrue(promo.get("attempted"))
            self.assertTrue(promo.get("staged"))
            self.assertTrue(rec["consent"]["confirmed"])
            buttons = [c for c in hid.calls if c[0] == "button"]
            self.assertIn(("button", "Home"), buttons)
            self.assertGreaterEqual(buttons.count(("button", "Power")), 2)

    def test_lock_promotion_regrant_merges_followup(self):
        # Always Allow follow-up surfaces after the relock: the
        # promotion regrant taps it and merges into consent taps.
        with tempfile.TemporaryDirectory() as tmp:
            docs = ([EMPTY_DOC] + [EMPTY_DOC] * (1 + ex.SHEET_WAIT_ROUNDS)
                    + [_desc_doc(("Allow", *ALLOW_XY)), EMPTY_DOC,
                       _desc_doc(("Always Allow", *ALWAYS_XY)), EMPTY_DOC])
            hid = FakeHidBackend(ax_script=docs)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_plain)]
                      + [("paint", paint_plain)] * 2
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-lock-regrant")
            self.assertEqual(summary["status"], "complete")
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())
            rec = live_capture_record(run_dir)
            promo = rec.get("lock_promotion") or {}
            self.assertTrue(promo.get("attempted"))
            self.assertTrue(promo.get("staged"))
            self.assertEqual((promo.get("regrant") or {}).get("outcome"),
                             "granted")
            labels = [t["label"] for t in rec["consent"]["taps"]]
            self.assertIn("Allow", labels)
            self.assertIn("Always Allow", labels)

    def test_lock_no_promotion_without_grant(self):
        # Blank lock with no grant (absent): no unlock-relock fires,
        # attempt evidence only with promotion.attempted False.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_plain)]
                      + [("paint", paint_plain)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-lock-nopromo")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual(len(_fake.io_calls), 3 + 1 + 3 + 1 + 2)
            rec = live_capture_record(run_dir)
            self.assertEqual(
                (rec.get("lock_attempt") or {}).get("outcome"), "no-banner")
            promo = ((rec.get("lock_attempt") or {}).get("promotion")
                     or rec.get("lock_promotion") or {})
            self.assertFalse(promo.get("attempted"))

    def test_lock_spawn_exhaustion_fails_closed(self):
        # Every lock export drops past the runner surface: bounded retry
        # exhausts into a named failure, the receipt stays partial, and
        # cleanup/restore/lease still run.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_plain)]
                      + [("raise", subprocess.TimeoutExpired("simctl", 60))]
                      * 3)
            udid = f"UDID-lockex-{os.getpid()}"
            container = Path(tmp) / "container"
            container.mkdir()
            fake = LiveFakeSimctl(container, io_script=script,
                                  la_block=dict(LA_BLOCK))
            run_dir = Path(tmp) / "runs" / "live-lock-3"
            with self.assertRaises(ex.FrameError) as ctx:
                ex.run_session(
                    fake, udid, base_request("live-lock-3"), "realtime",
                    run_dir, device_key="iphone63",
                    pinned_totals=dict(PINNED), geometry=GEO63,
                    session_nonce="6" * 32, hold_open=True, hid=hid,
                    interval_s=0.0, sleeper=ex.no_sleep, on_poll=fake.pump)
            self.assertIn("failed after 3 attempt", str(ctx.exception))
            receipt = json.loads(
                (run_dir / "sessions" / ("6" * 32 + ".receipt.json"))
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "partial")
            self.assertTrue(receipt["runner_verified"]["lease_released"])


class ConsentGateTests(unittest.TestCase):
    def _run(self, tmp, hid, compact_painter, run_id):
        return live_run(tmp, hid,
                        hold_script(compact_painter, paint_lock_banner),
                        run_id=run_id)

    def test_consent_sheet_surfaces_late_granted(self):
        # Under host load the sheet surfaces seconds after the first
        # describe: empty first tree waits bounded settle rounds (zero
        # taps while waiting), then the sheet grants normally.
        # Leading EMPTY_DOC is the pre-hold warm-up describe (discarded).
        with tempfile.TemporaryDirectory() as tmp:
            docs = [EMPTY_DOC, EMPTY_DOC,
                    _desc_doc(("Allow", *ALLOW_XY),
                              ("Don't Allow", 0.5, 0.9)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-late")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"],
                             [("tap", *ALLOW_XY)])
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "granted")
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_consent_absent_waits_bounded_zero_taps(self):
        # A truly absent sheet costs warmup(1) + foreground(1+1) +
        # lock(1+LOCK_SHEET_WAIT_ROUNDS) describes, then resolves absent
        # with zero taps.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax_script=[EMPTY_DOC])
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-absent-wait")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])
            n_ax = len([c for c in hid.calls if c[0] == "ax"])
            self.assertEqual(n_ax, 1 + 2 + (1 + ex.LOCK_SHEET_WAIT_ROUNDS))
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "absent")

    def test_consent_granted_via_describe_allow(self):
        # Sheet -> one tap at the describe-derived Allow center -> re-describe
        # verifies absence. Don't Allow rides along as sheet evidence only.
        # Leading EMPTY_DOC is the pre-hold warm-up describe (discarded).
        with tempfile.TemporaryDirectory() as tmp:
            docs = [EMPTY_DOC,
                    _desc_doc(("Allow", *ALLOW_XY),
                              ("Don't Allow", 0.5, 0.9)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-1")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"],
                             [("tap", *ALLOW_XY)])
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "granted")
            self.assertEqual(consent["rounds"], 1)
            self.assertEqual(len(consent["taps"]), 1)
            self.assertEqual(consent["taps"][0]["label"], "Allow")
            self.assertEqual((consent["taps"][0]["x"],
                              consent["taps"][0]["y"]), ALLOW_XY)
            # Lock capture (consent-independent) still lands genuine pixels.
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_consent_followup_always_allow_second_round(self):
        # Allow tap surfaces the follow-up; Always Allow is tapped in round
        # two and absence re-verified: granted with both coords recorded.
        # Leading EMPTY_DOC is the pre-hold warm-up describe (discarded).
        with tempfile.TemporaryDirectory() as tmp:
            docs = [EMPTY_DOC,
                    _desc_doc(("Allow", *ALLOW_XY)),
                    _desc_doc(("Always Allow", *ALWAYS_XY)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-5")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"],
                             [("tap", *ALLOW_XY), ("tap", *ALWAYS_XY)])
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "granted")
            self.assertEqual(consent["rounds"], 2)
            self.assertEqual([t["label"] for t in consent["taps"]],
                             ["Allow", "Always Allow"])

    def test_consent_two_round_exhaustion_blocker_capture_continues(self):
        # The sheet persists past the 2-tap bound: taps never loop, the
        # blocker is recorded, and lock/compact capture continues genuine.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(
                ax_script=[_desc_doc(("Allow", *ALLOW_XY))])
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-6")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"],
                             [("tap", *ALLOW_XY), ("tap", *ALLOW_XY)])
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "failed-blocker")
            self.assertEqual(consent["rounds"], 2)
            self.assertTrue(consent["blocker"])
            self.assertTrue(rec["compact"]["verdict"]["live"])
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_consent_dont_allow_never_tapped(self):
        # A sheet with no tappable Allow records a blocker with zero taps:
        # Don't Allow is evidence, never a tap target.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(
                ax_script=[_desc_doc(("Don't Allow", 0.5, 0.9))])
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-7")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "failed-blocker")
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_consent_malformed_describe_fails_closed_no_tap(self):
        # Malformed describe output (the ArgentHidBackend parse failure)
        # fails closed: no grant, no blind tap, capture still completes.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax_script=[
                ex.FrameError("describe document carries no text tree")])
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-8")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "failed-blocker")
            self.assertTrue(consent["blocker"])
            self.assertTrue(rec["compact"]["verdict"]["live"])
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_consent_absent_proceeds_without_tap(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = self._run(
                tmp, hid, paint_live_pill, "live-consent-2")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "absent")

    def test_no_pill_no_island_claim(self):
        # Compact screenshots without a live pill (idle mass, verdict
        # never live): all bounded reshoots stage honest pixels, but NO
        # island claim (no capture binding, stub stays pending).
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_idle_pill)] * 3
                      + [("paint", paint_plain)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-consent-4")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            self.assertFalse(rec["compact"]["verdict"]["live"])
            compact_png = run_dir / "staging" / "live-la-compact.png"
            self.assertTrue(compact_png.is_file())
            stub = json.loads(
                (run_dir / "frames" / "la-compact.json").read_text(
                    encoding="utf-8"))
            self.assertEqual(stub["capture"],
                             "external-lock-screen-pending")
            self.assertNotIn("capture_window", stub)


class CleanupWhileLockedTests(unittest.TestCase):
    def test_cleanup_runs_while_locked(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            fake, hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-clean-1")
            self.assertTrue(hid.locked, "driver must lock before cleanup")
            self.assertEqual(summary["status"], "complete")
            receipt = json.loads(
                (run_dir / "sessions" / f"{NONCE_LIVE}.receipt.json")
                .read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual(receipt["app_cleanup"]["status"], "cleaned")
            self.assertTrue(receipt["runner_verified"]["chrome_restored"])
            self.assertTrue(
                receipt["runner_verified"]["process_terminated"])
            self.assertTrue(receipt["runner_verified"]["lease_released"])


class ArgentHidBackendTests(unittest.TestCase):
    def test_rejects_non_capture_buttons(self):
        hid = ex.ArgentHidBackend("UDID-x", server="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.press_button("VolumeUp")

    def test_rejects_out_of_range_hold(self):
        hid = ex.ArgentHidBackend("UDID-x", server="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.multitouch_hold(0.4, 0.03, 1.5, 0.03)

    def test_rejects_out_of_range_long_press(self):
        hid = ex.ArgentHidBackend("UDID-x", argent="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.long_press(1.5, 0.5)
        with self.assertRaises(ex.FrameError):
            hid.long_press(0.5, 0.5, duration_ms=0)
        with self.assertRaises(ex.FrameError):
            hid.long_press(0.5, 0.5, duration_ms=True)

    def test_rejects_out_of_range_tap(self):
        hid = ex.ArgentHidBackend("UDID-x", server="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.tap(1.5, 0.5)

    def test_describe_missing_binary_fails_closed(self):
        hid = ex.ArgentHidBackend("UDID-x", argent="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.ax_dump()

    def test_tap_missing_binary_fails_closed(self):
        hid = ex.ArgentHidBackend("UDID-x", argent="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.tap(0.5, 0.5)

    def test_describe_and_tap_argv_pin_ci_invocations(self):
        # Scripted runner pins the exact `argent run describe` /
        # `gesture-tap` invocations the later CI wiring step reuses.
        from unittest import mock
        seen: list = []
        payloads = [
            {"description": '  AXButton "Allow"  '
                            "(0.650, 0.790, 0.134, 0.042)\n",
             "source": "ax-service"},
            {"description": "ROOT  AXGroup (0.000, 0.000, 1.000, 1.000)\n",
             "source": "ax-service"},
        ]

        def runner(argv):
            seen.append(list(argv))
            if argv[1:3] == ["run", "describe"]:
                return SimpleNamespace(returncode=0,
                                       stdout=json.dumps(payloads.pop(0)),
                                       stderr="")
            return SimpleNamespace(returncode=0,
                                   stdout='{"tapped": true}', stderr="")

        with mock.patch("shutil.which", return_value="/fake/argent"):
            hid = ex.ArgentHidBackend("UDID-x", runner=runner)
            tree = hid.ax_dump()
            self.assertEqual(ex.find_allow_button(tree), (0.717, 0.811))
            hid.tap(0.717, 0.811)
        self.assertEqual(seen[0][:5],
                         ["/fake/argent", "run", "describe",
                          "--udid", "UDID-x"])
        self.assertIn("--json", seen[0])
        self.assertEqual(seen[1][:5],
                         ["/fake/argent", "run", "gesture-tap",
                          "--udid", "UDID-x"])
        flat = " ".join(seen[1])
        self.assertIn("--x 0.717", flat)
        self.assertIn("--y 0.811", flat)

    def test_describe_malformed_output_fails_closed(self):
        from unittest import mock

        def runner(argv):
            return SimpleNamespace(returncode=0, stdout="not json",
                                   stderr="")

        with mock.patch("shutil.which", return_value="/fake/argent"):
            hid = ex.ArgentHidBackend("UDID-x", runner=runner)
            with self.assertRaises(ex.FrameError):
                hid.ax_dump()

    def test_long_press_argv_pins_gesture_custom(self):
        # Scripted runner pins the exact `argent run gesture-custom`
        # invocation the expanded step uses: Down/Up at the pill center
        # with delayMs 1200 (800ms pilot flaked), bounded runner timeout.
        from unittest import mock
        seen: list = []

        def runner(argv):
            seen.append(list(argv))
            return SimpleNamespace(returncode=0, stdout="{}", stderr="")

        with mock.patch("shutil.which", return_value="/fake/argent"):
            hid = ex.ArgentHidBackend("UDID-x", runner=runner)
            hid.long_press(0.5, 0.035)
        self.assertEqual(seen[0][:5],
                         ["/fake/argent", "run", "gesture-custom",
                          "--udid", "UDID-x"])
        flat = " ".join(seen[0])
        self.assertIn("--events-json", flat)
        payload = json.loads(seen[0][seen[0].index("--events-json") + 1])
        self.assertEqual(payload,
                         [{"type": "Down", "x": 0.5, "y": 0.035},
                          {"type": "Up", "x": 0.5, "y": 0.035,
                           "delayMs": 1200}])

    def test_long_press_missing_binary_fails_closed(self):
        hid = ex.ArgentHidBackend("UDID-x", argent="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.long_press(0.5, 0.035)

    def test_grant_end_to_end_over_argent_transport(self):
        # Full hold-open realtime session against a scripted argent runner:
        # warm-up describe (absent, discarded) then the sheet then
        # absence, gesture-tap + buttons + hold succeed, consent grants
        # with the proven center recorded.
        from unittest import mock
        seen: list = []
        payloads = [
            {"description": "ROOT  AXGroup (0.000, 0.000, 1.000, 1.000)\n",
             "source": "ax-service"},
            {"description": '  AXButton "Allow"  '
                            "(0.650, 0.790, 0.134, 0.042)\n"
                            '  AXButton "Don\'t Allow"  '
                            "(0.650, 0.840, 0.134, 0.042)\n",
             "source": "ax-service"},
            {"description": "ROOT  AXGroup (0.000, 0.000, 1.000, 1.000)\n",
             "source": "ax-service"},
        ]

        def runner(argv):
            seen.append(list(argv))
            if argv[1:3] == ["run", "describe"]:
                return SimpleNamespace(returncode=0,
                                       stdout=json.dumps(payloads.pop(0)),
                                       stderr="")
            return SimpleNamespace(returncode=0, stdout="{}", stderr="")

        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch("shutil.which",
                            return_value="/fake/argent"):
                hid = ex.ArgentHidBackend("UDID-e2e", runner=runner)
                _fake, _hid, run_dir, summary, _udid = live_run(
                    tmp, hid, hold_script(paint_live_pill),
                    run_id="live-e2e-1")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "granted")
            self.assertEqual(consent["rounds"], 1)
            self.assertEqual((consent["taps"][0]["x"],
                              consent["taps"][0]["y"]), (0.717, 0.811))
            gestures = [c for c in seen if c[1:3] == ["run", "gesture-tap"]]
            self.assertEqual(len(gestures), 1)
            self.assertTrue(rec["compact"]["verdict"]["live"])
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_missing_server_binary_fails_closed(self):
        hid = ex.ArgentHidBackend("UDID-x", server="definitely-missing-bin")
        with self.assertRaises(ex.FrameError):
            hid.press_button("Power")


class CliHoldOpenTests(unittest.TestCase):
    def _ns(self, tmp, **over):
        import argparse
        base = dict(out=tmp, run_id="live-cli-1",
                    device="UDID-x", device_key="iphone63",
                    request=str(Path(tmp) / "base.json"), domain="realtime",
                    geometry="1206x2622",
                    pinned_totals=str(Path(tmp) / "pin.json"),
                    island=None, bid=rs.SCREENSHOT_BID, approval=None,
                    retained_dir=None, timeout=ex.POLL_TIMEOUT_S,
                    interval=ex.POLL_INTERVAL_S, hold_open=False)
        base.update(over)
        return argparse.Namespace(**base)

    def test_hold_open_rejects_pinned_before_lease(self):
        import capture as cap_mod
        with tempfile.TemporaryDirectory() as tmp:
            ns = self._ns(tmp, domain="pinned", hold_open=True)
            saved = os.environ.pop(cap_mod.LEASE_ENV, None)
            try:
                self.assertEqual(cap_mod.cmd_run_session(ns),
                                 cap_mod.EXIT_INVALID)
            finally:
                if saved is not None:
                    os.environ[cap_mod.LEASE_ENV] = saved


class ExpandedHoldTests(unittest.TestCase):
    def test_card_stages_with_hold_proof(self):
        # Live pill + single-finger long-press renders a genuine card:
        # staged with pixel verification, and the hold is a gesture-custom
        # long-press at the pill center (never a tap — a tap would open
        # the app instead of expanding; never multitouch — proven
        # incapable). First-attempt pass stages with attempts == 1.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_expanded_card)]
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-exp-1")
            self.assertEqual(summary["status"], "complete")
            staged = run_dir / "staging" / "live-la-expanded.png"
            self.assertTrue(staged.is_file())
            rec = live_capture_record(run_dir)
            self.assertIn("expanded", rec)
            self.assertNotIn("expanded_attempt", rec)
            self.assertTrue(rec["expanded"]["verdict"]["expanded"])
            presses = [c for c in hid.calls if c[0] == "long-press"]
            self.assertEqual(len(presses), 1)
            _, x, y, dur = presses[0]
            self.assertEqual(dur, 1200)
            px0, px1, py0, py1 = PILL_BOX
            self.assertGreaterEqual(x, px0 / GEO63[0])
            self.assertLessEqual(x, px1 / GEO63[0])
            self.assertGreaterEqual(y, py0 / GEO63[1])
            self.assertLessEqual(y, py1 / GEO63[1])
            self.assertEqual(rec["expanded"]["hold"],
                             {"x": x, "y": y, "duration_ms": 1200})
            self.assertEqual(rec["expanded"].get("attempts"), 1)
            self.assertEqual([c for c in hid.calls if c[0] == "hold"], [])
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])
            self.assertLess(hid.calls.index(presses[0]),
                            hid.calls.index(("button", "Power")))
            # Lock/compact undisturbed by the staged card.
            self.assertTrue(
                (run_dir / "staging" / "live-la-compact.png").is_file())
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())
            self.assertTrue(rec["compact"]["verdict"]["live"])

    def test_no_card_no_staging_lock_undisturbed(self):
        # Live pill + long-press with no card mass across all 3 verdict-gated
        # attempts: no staging, honest no-card attempt recorded (last probe
        # kept), lock/compact undisturbed.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill), run_id="live-exp-2")
            self.assertEqual(summary["status"], "complete")
            self.assertFalse(
                (run_dir / "staging" / "live-la-expanded.png").is_file())
            self.assertTrue(
                (run_dir / "staging" / "live-la-expanded.attempt.png")
                .is_file())
            rec = live_capture_record(run_dir)
            self.assertNotIn("expanded", rec)
            attempt = rec["expanded_attempt"]
            self.assertEqual(attempt["outcome"], "no-card")
            self.assertTrue(attempt["pre_live"])
            self.assertEqual(attempt["hold"]["duration_ms"], 1200)
            self.assertEqual(attempt.get("attempts"), 3)
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "long-press"]), 3)
            self.assertEqual([c for c in hid.calls if c[0] == "hold"], [])
            self.assertTrue(
                (run_dir / "staging" / "live-la-compact.png").is_file())
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())
            powers = [c for c in hid.calls if c == ("button", "Power")]
            self.assertEqual(len(powers), 2)

    def test_tap_opened_app_refused(self):
        # Pre-hold pill live, but post-hold pixels show uniform app chrome
        # with the pill hidden (the press behaved as a tap and opened the
        # Timer screen): expansion refused on pixels over all 3 attempts,
        # lock still genuine, nothing staged.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_app_screen)] * 3
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-exp-3")
            self.assertEqual(summary["status"], "complete")
            self.assertFalse(
                (run_dir / "staging" / "live-la-expanded.png").is_file())
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["expanded_attempt"]["outcome"], "no-card")
            self.assertIn("app", rec["expanded_attempt"]["reason"])
            self.assertEqual(rec["expanded_attempt"]["hold"]
                             ["duration_ms"], 1200)
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "long-press"]), 3)
            self.assertEqual([c for c in hid.calls if c[0] == "hold"], [])
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_no_pre_pill_no_hold_fired(self):
        # No confirmed pre-hold pill: no long-press fires (a blind
        # long-press could jiggle Home), no staging, lock proceeds
        # undisturbed.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_idle_pill)] * 3
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-exp-4")
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([c for c in hid.calls
                              if c[0] == "long-press"], [])
            self.assertEqual([c for c in hid.calls if c[0] == "hold"], [])
            self.assertFalse(
                (run_dir / "staging" / "live-la-expanded.png").is_file())
            self.assertFalse(
                (run_dir / "staging" / "live-la-expanded.attempt.png")
                .is_file())
            rec = live_capture_record(run_dir)
            self.assertIn("no hold fired",
                          rec["expanded_attempt"]["reason"])
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_retry_succeeds_second_attempt(self):
        # Flaky first Down (transition frame, no card) then a genuine card
        # on the second verdict-gated attempt: staged on first pass with
        # attempts == 2, both holds at 1200ms, lock/compact undisturbed.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)]
                      + [("paint", paint_expanded_card)]
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-exp-5")
            self.assertEqual(summary["status"], "complete")
            staged = run_dir / "staging" / "live-la-expanded.png"
            self.assertTrue(staged.is_file())
            rec = live_capture_record(run_dir)
            self.assertIn("expanded", rec)
            self.assertTrue(rec["expanded"]["verdict"]["expanded"])
            self.assertEqual(rec["expanded"].get("attempts"), 2)
            presses = [c for c in hid.calls if c[0] == "long-press"]
            self.assertEqual(len(presses), 2)
            for _, x, y, dur in presses:
                self.assertEqual(dur, 1200)
                px0, px1, py0, py1 = PILL_BOX
                self.assertGreaterEqual(x, px0 / GEO63[0])
                self.assertLessEqual(x, px1 / GEO63[0])
                self.assertGreaterEqual(y, py0 / GEO63[1])
                self.assertLessEqual(y, py1 / GEO63[1])
            self.assertEqual(rec["expanded"]["hold"]["duration_ms"], 1200)
            self.assertTrue(
                (run_dir / "staging" / "live-la-compact.png").is_file())
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_triple_miss_records_attempt_honestly(self):
        # Three plain verdict-gated attempts, no card mass anywhere: no
        # staging, the LAST attempt PNG kept as evidence with attempts == 3
        # and the 1200ms hold recorded honestly.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-exp-6")
            self.assertEqual(summary["status"], "complete")
            self.assertFalse(
                (run_dir / "staging" / "live-la-expanded.png").is_file())
            attempt_png = run_dir / "staging" / "live-la-expanded.attempt.png"
            self.assertTrue(attempt_png.is_file())
            rec = live_capture_record(run_dir)
            self.assertNotIn("expanded", rec)
            attempt = rec["expanded_attempt"]
            self.assertEqual(attempt["outcome"], "no-card")
            self.assertTrue(attempt["pre_live"])
            self.assertEqual(attempt["hold"]["duration_ms"], 1200)
            self.assertEqual(attempt.get("attempts"), 3)
            self.assertEqual(attempt["probe"],
                             "staging/live-la-expanded.attempt.png")
            self.assertTrue(attempt["captured_at_iso"])
            presses = [c for c in hid.calls if c[0] == "long-press"]
            self.assertEqual(len(presses), 3)
            self.assertTrue(all(p[3] == 1200 for p in presses))
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_hold_duration_carries_1200ms(self):
        # Every expanded Down/Up in the verdict-gated loop carries 1200ms
        # (800ms pilot flaked): single-pass and triple-miss agree.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = hold_script(paint_live_pill,
                                 expanded_painter=paint_expanded_card)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-exp-7")
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["expanded"]["hold"]["duration_ms"], 1200)
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill), run_id="live-exp-8")
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["expanded_attempt"]["hold"]
                             ["duration_ms"], 1200)


class ConsentDismissalTests(unittest.TestCase):
    def test_sheet_absent_no_tap(self):
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-sheet-1")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent_dismissal"]["outcome"], "absent")
            self.assertEqual(rec["consent_dismissal"]["attempts"], 0)
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])

    def test_sheet_dismissed_via_pixel_centroid(self):
        # The Allow tap point comes from the live probe image (label
        # centroid), verified by re-shot; lock capture stays genuine.
        # Expanded takes up to 3 verdict-gated shots, so the sheet probe
        # sits after 3 plain expanded attempts.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_sheet)]
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-sheet-2")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            dis = rec["consent_dismissal"]
            self.assertEqual(dis["outcome"], "dismissed")
            self.assertEqual(dis["attempts"], 1)
            taps = [c for c in hid.calls if c[0] == "tap"]
            self.assertEqual(len(taps), 1)
            lx0, lx1, ly0, ly1 = SHEET_LABEL
            self.assertAlmostEqual(taps[0][1], (lx0 + lx1) / 2 / GEO63[0],
                                   delta=0.02)
            self.assertAlmostEqual(taps[0][2], (ly0 + ly1) / 2 / GEO63[1],
                                   delta=0.02)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_sheet_blocked_after_one_tap_lock_genuine(self):
        # One pixel-derived tap fails with evidence: blocked recorded
        # honestly (taps never loop), lock pixels still staged genuine.
        # Expanded takes up to 3 verdict-gated shots, so the sheet probe
        # sits after 3 plain expanded attempts.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            script = ([("paint", paint_plain)] * 3
                      + [("paint", paint_live_pill)]
                      + [("paint", paint_plain)] * 3
                      + [("paint", paint_sheet)] * 2
                      + [("paint", paint_plain)]
                      + [("paint", paint_lock_banner)] * 2)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, script, run_id="live-sheet-3")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            dis = rec["consent_dismissal"]
            self.assertEqual(dis["outcome"], "blocked")
            self.assertEqual(dis["attempts"], 1)
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "tap"]), 1)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())


class LockPhaseConsentTests(unittest.TestCase):
    """Lock-time re-grant: foreground absent, sheet surfaces once locked.

    The clean-sim run proved the sheet surfaces at LOCK time, after the
    foreground describe already returned absent. run_live_capture re-runs
    the same grant_consent helper after the power press and before any
    lock screenshot (per-phase max 2 taps, total ≤4). The foreground
    attempt is NOT moved and the pixel-dismissal probe stays as-is.
    """

    def _run_lock_phase(self, tmp, hid, run_id):
        return live_run(tmp, hid,
                        hold_script(paint_live_pill, paint_lock_banner),
                        run_id=run_id)

    def test_lock_phase_grant_fires_on_scripted_lock_time_sheet(self):
        # Foreground absent, lock-time Allow tapped at describe-derived
        # center; the tap fires after the Power lock, before lock pixels.
        # Leading EMPTY_DOC is the pre-hold warm-up describe (discarded).
        with tempfile.TemporaryDirectory() as tmp:
            # Foreground consumes 2 EMPTYs (1 + 1 wait round) before
            # resolving absent, so the lock-time sheet needs padding.
            docs = [EMPTY_DOC] + [EMPTY_DOC] * (1 + ex.SHEET_WAIT_ROUNDS) + [
                    _desc_doc(("Allow", *ALLOW_XY)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-1")
            self.assertEqual(summary["status"], "complete")
            taps = [c for c in hid.calls if c[0] == "tap"]
            self.assertEqual(taps, [("tap", *ALLOW_XY)])
            powers = [i for i, c in enumerate(hid.calls)
                      if c == ("button", "Power")]
            self.assertEqual(len(powers), 2)
            tap_idx = hid.calls.index(taps[0])
            self.assertGreater(tap_idx, powers[-1],
                               "lock-phase tap must fire once locked")
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_foreground_absent_lock_granted_outcome(self):
        # Foreground absent + lock granted: merged outcome granted,
        # phase lock, foreground/lock audit preserved, total ≤4.
        with tempfile.TemporaryDirectory() as tmp:
            # Foreground consumes 2 EMPTYs (1 + 1 wait round) before
            # resolving absent, so the lock-time sheet needs padding.
            docs = [EMPTY_DOC] + [EMPTY_DOC] * (1 + ex.SHEET_WAIT_ROUNDS) + [
                    _desc_doc(("Allow", *ALLOW_XY)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-2")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "granted")
            self.assertEqual(consent["phase"], "lock")
            self.assertEqual(consent["rounds"], 1)
            self.assertEqual(len(consent["taps"]), 1)
            self.assertEqual(consent["taps"][0]["label"], "Allow")
            self.assertEqual((consent["taps"][0]["x"],
                              consent["taps"][0]["y"]), ALLOW_XY)
            self.assertEqual(consent["foreground"]["outcome"], "absent")
            self.assertEqual(consent["lock"]["outcome"], "granted")
            self.assertLessEqual(len(consent["taps"]), 4)
            self.assertTrue(rec["compact"]["verdict"]["live"])
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_total_tap_bound(self):
        # Worst honest paths stay within total ≤4 (per-phase max 2):
        # absent foreground (0) + persisting lock sheet (2) = 2;
        # granted foreground (1) + skipped lock (0) = 1;
        # persisting foreground (2) + skipped lock (0) = 2.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(
                ax_script=[EMPTY_DOC, EMPTY_DOC,
                           _desc_doc(("Allow", *ALLOW_XY))])
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-3")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "failed-blocker")
            self.assertIsNone(consent["phase"])
            self.assertLessEqual(len(consent["taps"]), 4)
            self.assertEqual(len(consent["taps"]), 2)
        with tempfile.TemporaryDirectory() as tmp:
            docs = [EMPTY_DOC,
                    _desc_doc(("Allow", *ALLOW_XY),
                              ("Don't Allow", 0.5, 0.9)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-4")
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "granted")
            self.assertEqual(rec["consent"]["phase"], "foreground")
            self.assertLessEqual(len(rec["consent"]["taps"]), 4)
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(
                ax_script=[_desc_doc(("Allow", *ALLOW_XY))])
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-5")
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "failed-blocker")
            self.assertLessEqual(len(rec["consent"]["taps"]), 4)
            self.assertEqual(len(rec["consent"]["taps"]), 2)

    def test_foreground_granted_skips_lock(self):
        # Already-surfaced sheet granted up front: no lock-phase HID,
        # phase foreground, tap before any Power (existing loop green).
        # Leading EMPTY_DOC is the pre-hold warm-up describe (discarded).
        with tempfile.TemporaryDirectory() as tmp:
            docs = [EMPTY_DOC,
                    _desc_doc(("Allow", *ALLOW_XY),
                              ("Don't Allow", 0.5, 0.9)), EMPTY_DOC]
            hid = FakeHidBackend(ax_script=docs)
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-6")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "granted")
            self.assertEqual(consent["phase"], "foreground")
            self.assertIsNone(consent["lock"])
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "ax"]), 3)
            taps = [c for c in hid.calls if c[0] == "tap"]
            self.assertEqual(len(taps), 1)
            powers = [i for i, c in enumerate(hid.calls)
                      if c == ("button", "Power")]
            self.assertLess(hid.calls.index(taps[0]), powers[0])

    def test_foreground_blocker_skips_lock(self):
        # Persisting foreground sheet (2-tap bound): taps never loop into
        # lock, blocker recorded, capture continues genuine.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(
                ax_script=[_desc_doc(("Allow", *ALLOW_XY))])
            _fake, _hid, run_dir, summary, _udid = self._run_lock_phase(
                tmp, hid, "live-lockphase-7")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "failed-blocker")
            self.assertIsNone(consent["phase"])
            self.assertIsNone(consent["lock"])
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "tap"]), 2)
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "ax"]), 4)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())


class ExpandedVerdictTests(unittest.TestCase):
    def _shot(self, tmp, painter, name="v.png"):
        path = Path(tmp) / name
        painter(path)
        return str(path)

    def test_card_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = ex.expanded_verdict(self._shot(tmp, paint_expanded_card),
                                    GEO63)
            self.assertTrue(v["expanded"], v)

    def test_plain_no_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = ex.expanded_verdict(self._shot(tmp, paint_plain), GEO63)
            self.assertFalse(v["expanded"], v)

    def test_app_screen_refused_as_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = ex.expanded_verdict(self._shot(tmp, paint_app_screen),
                                    GEO63)
            self.assertFalse(v["expanded"], v)
            g = ex.app_foreground_verdict(self._shot(tmp, paint_app_screen),
                                          GEO63)
            self.assertTrue(g["app"], g)
            g2 = ex.app_foreground_verdict(
                self._shot(tmp, paint_live_pill), GEO63)
            self.assertFalse(g2["app"], g2)

    def test_sheet_centroid_from_pixels(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = ex.find_allow_centroid(self._shot(tmp, paint_sheet),
                                           GEO63)
            self.assertTrue(found["found"], found)
            lx0, lx1, ly0, ly1 = SHEET_LABEL
            self.assertAlmostEqual(found["x"], (lx0 + lx1) / 2 / GEO63[0],
                                   delta=0.02)
            self.assertAlmostEqual(found["y"], (ly0 + ly1) / 2 / GEO63[1],
                                   delta=0.02)
            missing = ex.find_allow_centroid(
                self._shot(tmp, paint_plain, name="p.png"), GEO63)
            self.assertFalse(missing["found"], missing)


class DescribeParserTests(unittest.TestCase):
    # Fixture lines follow the observed `argent run describe` grammar
    # (role, quoted label, optional attrs, normalized frame). The frames
    # below derive the scratch-sim proven centers: compact Allow
    # (0.717, 0.811), follow-up Always Allow (0.7235, 0.82).
    SHEET_TEXT = (
        "Source: ax-service\n"
        "Mode: flat\n"
        "Coordinates are normalized [0,1] fractions of the screen "
        "(x, y, width, height), not pixels.\n"
        "Pass them straight to gesture-tap / gesture-swipe / "
        "gesture-pinch, which expect this same space.\n"
        "To tap an element, use its centre: tap_x = frame.x + "
        "frame.width / 2, tap_y = frame.y + frame.height / 2.\n"
        "\n"
        "ROOT  AXGroup (0.000, 0.000, 1.000, 1.000)\n"
        "\n"
        '  AXStaticText "Allow Live Activities from Lifio?"  '
        "(0.500, 0.700, 0.300, 0.030)\n"
        '  AXButton "Allow"  (0.650, 0.790, 0.134, 0.042)\n'
        '  AXButton "Don\'t Allow" id="dont-allow"  '
        "(0.650, 0.840, 0.134, 0.042)\n")

    FOLLOWUP_TEXT = (
        "ROOT  AXGroup (0.000, 0.000, 1.000, 1.000)\n"
        '  AXStaticText "Do you want to continue to allow Live '
        'Activities from Lifio?"  (0.500, 0.700, 0.300, 0.030)\n'
        '  AXButton "Always Allow" value="always"  '
        "(0.660, 0.799, 0.127, 0.042)\n")

    def test_allow_center_from_frame(self):
        buttons = ex.parse_describe_buttons(self.SHEET_TEXT)
        by_label = {b["label"]: b for b in buttons}
        self.assertEqual(sorted(by_label), ["Allow", "Don't Allow"])
        allow = by_label["Allow"]
        self.assertAlmostEqual(allow["center"][0], 0.717, places=9)
        self.assertAlmostEqual(allow["center"][1], 0.811, places=9)
        self.assertEqual(ex.find_allow_button(
            {"source": "ax-service", "buttons": buttons}), (0.717, 0.811))

    def test_followup_always_allow_center(self):
        buttons = ex.parse_describe_buttons(self.FOLLOWUP_TEXT)
        self.assertEqual(len(buttons), 1)
        self.assertEqual(buttons[0]["label"], "Always Allow")
        self.assertAlmostEqual(buttons[0]["center"][0], 0.7235, places=9)
        self.assertAlmostEqual(buttons[0]["center"][1], 0.82, places=9)
        # Exact-label matching: the follow-up is not an Allow match.
        self.assertIsNone(ex.find_allow_button(
            {"source": "ax-service", "buttons": buttons}))
        self.assertEqual(
            ex.find_consent_button(
                {"source": "ax-service", "buttons": buttons},
                "always allow"),
            (0.7235, 0.82))

    def test_non_button_lines_ignored(self):
        buttons = ex.parse_describe_buttons(
            "Source: ax-service\nMode: flat\n"
            "ROOT  AXGroup (0.000, 0.000, 1.000, 1.000)\n"
            '  AXStaticText "Allow"  (0.500, 0.700, 0.300, 0.030)\n'
            '  AXGroup "Allow"  (0.500, 0.700, 0.300, 0.030)\n')
        self.assertEqual(buttons, [])

    def test_exact_label_matching(self):
        text = ('  AXButton "Allowed"  (0.1, 0.1, 0.1, 0.1)\n'
                '  AXButton "allow me"  (0.1, 0.2, 0.1, 0.1)\n'
                '  AXButton "ALLOW"  (0.650, 0.790, 0.134, 0.042)\n')
        buttons = ex.parse_describe_buttons(text)
        self.assertEqual([b["label"] for b in buttons],
                         ["Allowed", "allow me", "ALLOW"])
        doc = {"source": "ax-service", "buttons": buttons}
        # Casefold exact "allow" matches; near-misses never match.
        self.assertEqual(ex.find_allow_button(doc), (0.717, 0.811))
        self.assertEqual(ex.collect_consent_buttons(doc)[0][:2],
                         ("allow", "ALLOW"))

    def test_smart_quote_dont_allow_normalized(self):
        buttons = ex.parse_describe_buttons(
            '  AXButton "Don\u2019t Allow"  (0.1, 0.1, 0.1, 0.1)\n')
        rows = ex.collect_consent_buttons(
            {"source": "ax-service", "buttons": buttons})
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][0], "don't allow")

    def test_value_attr_label_parsed(self):
        buttons = ex.parse_describe_buttons(
            '  AXButton value="Allow" id="allow-btn"  '
            "(0.650, 0.790, 0.134, 0.042)\n")
        self.assertEqual(len(buttons), 1)
        self.assertEqual(buttons[0]["label"], "Allow")

    def test_out_of_range_frame_ignored(self):
        buttons = ex.parse_describe_buttons(
            '  AXButton "Allow"  (0.650, 0.790, 1.134, 0.042)\n'
            '  AXButton "Allow"  (0.650, 0.790, 0.134, 0.042)\n')
        self.assertEqual(len(buttons), 1)
        self.assertEqual(buttons[0]["center"], [0.717, 0.811])

    def test_malformed_document_fails_closed(self):
        for bad in ({}, {"description": None}, {"description": "   "},
                    {"source": "ax-service"}, "not-a-dict", None, 42):
            with self.assertRaises(ex.FrameError, msg=repr(bad)):
                ex.parse_describe_document(bad)
        with self.assertRaises(ex.FrameError):
            ex.parse_describe_buttons(None)
        with self.assertRaises(ex.FrameError):
            ex.parse_describe_buttons(b"\x00binary")


class PillVerifyTests(unittest.TestCase):
    def _shot(self, tmp, painter, name="pill.png"):
        path = Path(tmp) / name
        painter(path)
        return str(path)

    def test_live_pill_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            verdict = ex.island_verdict(self._shot(tmp, paint_live_pill),
                                        GEO63)
            self.assertTrue(verdict["live"], verdict)
            self.assertGreaterEqual(verdict["dark_frac"], 0.40)

    def test_idle_pill_not_live(self):
        with tempfile.TemporaryDirectory() as tmp:
            verdict = ex.island_verdict(self._shot(tmp, paint_idle_pill),
                                        GEO63)
            self.assertFalse(verdict["live"], verdict)
            self.assertIn("without live content", verdict["reason"])

    def test_no_pill_mass_no_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            verdict = ex.island_verdict(
                self._shot(tmp, paint_plain), GEO63)
            self.assertFalse(verdict["live"], verdict)
            self.assertIn("no pill", verdict["reason"])

    def test_unattested_geometry_no_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            verdict = ex.island_verdict(
                self._shot(tmp, paint_live_pill), (2064, 2752))
            self.assertFalse(verdict["live"], verdict)
            self.assertIn("unattested", verdict["reason"])

    def test_find_allow_button(self):
        self.assertEqual(ex.find_allow_button(ALLOW_TREE), (0.5, 0.9))
        self.assertIsNone(ex.find_allow_button({"label": "root"}))
        self.assertIsNone(ex.find_allow_button({}))
        # Describe-derived shapes: center pair and frame quad (derived).
        center_doc = {"source": "ax-service", "buttons": [
            {"role": "AXButton", "label": "Allow",
             "center": [0.717, 0.811],
             "frame": [0.65, 0.79, 0.134, 0.042]}]}
        self.assertEqual(ex.find_allow_button(center_doc), (0.717, 0.811))
        frame_only = {"source": "ax-service", "buttons": [
            {"role": "AXButton", "label": "Allow",
             "frame": [0.65, 0.79, 0.134, 0.042]}]}
        found = ex.find_allow_button(frame_only)
        self.assertAlmostEqual(found[0], 0.717, places=9)
        self.assertAlmostEqual(found[1], 0.811, places=9)


class ColdStartFixTests(unittest.TestCase):
    """Run 42051429064 (iphone69-en) cold-start fix: warm-up + 30s describe
    with one retry + hid_ms timings. No real sleeps; scripted clocks only.
    """

    def _session_record(self, run_dir):
        return json.loads(
            (run_dir / "sessions" / f"{NONCE_LIVE}.json")
            .read_text(encoding="utf-8"))

    def test_warmup_success_result_discarded_hold_proceeds(self):
        # Warm-up describe carries an Allow sheet but is discarded: the
        # consent phases see absent and the hold still completes. Proves
        # the daemon call is issued pre-hold (first ax) with its result
        # unused.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax_script=[
                _desc_doc(("Allow", *ALLOW_XY)),
                EMPTY_DOC, EMPTY_DOC])
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-warm-1")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "absent")
            self.assertEqual([c for c in hid.calls if c[0] == "tap"], [])
            ax_idx = [i for i, c in enumerate(hid.calls) if c[0] == "ax"]
            self.assertGreaterEqual(len(ax_idx), 3)
            self.assertEqual(ax_idx[0], 0)
            session_rec = self._session_record(run_dir)
            self.assertEqual(
                session_rec["hold_open"].get("warmup", {}).get("status"),
                "ok")
            hid_ms = summary["stats"].get("hid_ms", [])
            warmups = [e for e in hid_ms if e["op"] == "describe-warmup"]
            self.assertEqual(len(warmups), 1)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_warmup_failure_recorded_session_continues(self):
        # Cold-daemon warm-up timeout is recorded honestly and never
        # aborts: the hold driver still tries and completes.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax_script=[
                ex.FrameError("HID describe spawn failed (TimeoutExpired)"),
                EMPTY_DOC, EMPTY_DOC])
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-warm-2")
            self.assertEqual(summary["status"], "complete")
            session_rec = self._session_record(run_dir)
            warmup = session_rec["hold_open"].get("warmup", {})
            self.assertEqual(warmup.get("status"), "warmup_failed")
            self.assertTrue(warmup.get("detail"))
            rec = live_capture_record(run_dir)
            self.assertEqual(rec["consent"]["outcome"], "absent")
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_describe_timeout_single_retry_success(self):
        # Foreground initial describe times out once; the single retry
        # serves Allow, the tap lands, absence verifies: granted with
        # exactly one retry (4 ax total: warm-up + fail + retry + verify).
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax_script=[
                EMPTY_DOC,
                ex.FrameError("HID describe spawn failed (TimeoutExpired)"),
                _desc_doc(("Allow", *ALLOW_XY)), EMPTY_DOC])
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-retry-1")
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "granted")
            self.assertEqual(consent["phase"], "foreground")
            self.assertEqual(len(consent["taps"]), 1)
            self.assertEqual((consent["taps"][0]["x"],
                              consent["taps"][0]["y"]), ALLOW_XY)
            self.assertEqual(len([c for c in hid.calls
                                  if c[0] == "ax"]), 4)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_double_timeout_failed_blocker_within_budget(self):
        # Two back-to-back 30s describe timeouts in one phase degrade to
        # failed-blocker (capture proceeds) with total describe budget
        # <=60s. Scripted clock only: each timeout advances 30s, no real
        # sleeps.
        with tempfile.TemporaryDirectory() as tmp:
            t = [1000.0]
            clock = lambda: t[0]  # noqa: E731
            tick = lambda s: t.__setitem__(0, t[0] + s)  # noqa: E731
            hid = FakeHidBackend(
                ax_script=[EMPTY_DOC,
                           ex.FrameError("HID describe spawn failed "
                                         "(TimeoutExpired)"),
                           ex.FrameError("HID describe spawn failed "
                                         "(TimeoutExpired)")],
                tick=tick, timeout_s=ex.DESCRIBE_TIMEOUT_S)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-retry-2", clock=clock,
                hold_timeout_s=120.0)
            self.assertEqual(summary["status"], "complete")
            rec = live_capture_record(run_dir)
            consent = rec["consent"]
            self.assertEqual(consent["outcome"], "failed-blocker")
            self.assertEqual(len(consent["taps"]), 0)
            self.assertLessEqual(t[0] - 1000.0, ex.DESCRIBE_BUDGET_S + 1e-6)
            hid_ms = summary["stats"].get("hid_ms", [])
            describes = [e for e in hid_ms if e["op"] == "describe"]
            self.assertEqual(len(describes), 2)
            self.assertLessEqual(sum(e["ms"] for e in describes),
                                 ex.DESCRIBE_BUDGET_S * 1000.0 + 1e-6)
            self.assertTrue(
                (run_dir / "staging" / "live-la-lock.png").is_file())

    def test_hid_ms_present_for_every_hid_op(self):
        # Every HID call in a complete hold leaves one {op, ms} entry:
        # counts match the fake call log and cover all op families.
        with tempfile.TemporaryDirectory() as tmp:
            hid = FakeHidBackend(ax=None)
            _fake, _hid, run_dir, summary, _udid = live_run(
                tmp, hid, hold_script(paint_live_pill),
                run_id="live-hidms-1")
            self.assertEqual(summary["status"], "complete")
            hid_ms = summary["stats"].get("hid_ms", [])
            self.assertEqual(len(hid_ms), len(hid.calls))
            for entry in hid_ms:
                self.assertIn("op", entry)
                self.assertIn("ms", entry)
                self.assertGreaterEqual(entry["ms"], 0.0)
            ops = {e["op"] for e in hid_ms}
            self.assertIn("describe-warmup", ops)
            self.assertIn("describe", ops)
            self.assertIn("press_button", ops)
            self.assertIn("long_press", ops)
            session_rec = self._session_record(run_dir)
            self.assertEqual(session_rec["stats"].get("hid_ms"), hid_ms)


if __name__ == "__main__":
    unittest.main()
