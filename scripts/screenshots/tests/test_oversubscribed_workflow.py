#!/usr/bin/env python3
"""Oversubscribed-workflow scheduling regression (task 7.4, UNIT model).

Proves the no-drop contract the counting-only describe_capacity cannot:
with SIX selected devices and FEWER runner slots, every selected
device/pair/pass/domain still executes EXACTLY once — queued work is
retained until a slot frees, never silently shrunk to fit capacity.

What this is (read carefully before citing it anywhere):
- A UNIT model of worker queueing: worker threads contend on a
  threading.Semaphore(capacity) with threading.Barrier rendezvous
  (deterministic overlap proof, NO sleeps, NO timing dependence).
  It is NOT real GitHub contention, NOT competitor visibility, and
  proves NOTHING about actual queue waiting time. Real queue capacity
  is measured in 8.x on live runs. Single-pass scope (§9): six
  devices × one locale × one pass × two domains = 12 sessions.
- Every job invokes the REAL production `run_device_worker.execute`
  with an injected fake subprocess/env and the REAL capture.py CLI
  path (never executed — the fake answers). Statuses, run IDs, and
  work records asserted below come from that real worker code, so a
  worker that silently skipped inputs would fail here. This tests the
  production scheduling path, not a custom scheduler in isolation.
- The 6-device catalog is a TEMPORARY in-test patch of the supported
  future set (restored after each test); production catalogs are
  untouched. Locales stay (["en"]) and the runtime stays pinned.
- max-parallel comes from the LOCAL sequential driver constant below
  (owner decision: capture runs locally, strictly sequential, one
  simulator at a time — no CI matrix exists anymore); the model
  capacity is min(available, LOCAL_SLOTS). Same stdlib technique as
  before, no second hardcoded definition per test.

Red-oracle note: test_truncation_mutation_detected feeds a 5-of-6
mutated selection through the same completeness check and asserts the gap
is DETECTED. That is the red demonstration for silent shrinking: had
the worker (or selection) dropped a device, this is the failure the
suite would show. It does not pretend an actual bug was reproduced.
"""

import json
import re
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import run_device_worker as rw
import workflow_artifacts as wa
import workflow_inputs as wi

LOCAL_SLOTS = 1


def local_max_parallel() -> int:
    return LOCAL_SLOTS

FUTURE_DEVICES = {
    # Temporary 6-device future catalog (production: 3). Geometries are
    # real matrix sizes; the fake backend never renders pixels.
    "iphone61": {"sim": "iPhone 16 Pro", "geometry": "1320x2868",
                 "island": 1},
    "iphone58": {"sim": "iPhone 14", "geometry": "1206x2622", "island": 1},
    "ipad11": {"sim": "iPad Air 11-inch (M4)", "geometry": "2064x2752",
               "island": 0},
}
SIX_DEVICES = ["iphone69", "iphone63", "ipad13", "iphone61", "iphone58",
               "ipad11"]
LOCALES = ["en"]
# Single automated pass per pair (§9): mirrors the production
# workflow_inputs.PASSES single source (6 devices × 1 locale × 1 pass
# × 2 domains = 12 sessions, not 24).
PASSES = ("r1",)
DOMAINS = ("pinned", "realtime")
THREAD_TIMEOUT = 120.0


def local_max_parallel() -> int:
    return LOCAL_SLOTS


class SixDeviceCatalog(unittest.TestCase):
    """Context helper is exercised through setUp/tearDown patching."""

    def setUp(self):
        self._old_devices = wi.SUPPORTED_DEVICES
        self._old_catalog = dict(wi.DEVICE_CATALOG)
        wi.SUPPORTED_DEVICES = tuple(SIX_DEVICES)
        catalog = dict(wi.DEVICE_CATALOG)
        catalog.update(FUTURE_DEVICES)
        wi.DEVICE_CATALOG = catalog
        self.addCleanup(self._restore)

    def _restore(self):
        wi.SUPPORTED_DEVICES = self._old_devices
        wi.DEVICE_CATALOG = self._old_catalog


class FakeBackend:
    """Injected subprocess backend: instant rc, full call ledger.

    `fail` maps device_key -> "rc" (nonzero child rc on run-session) or
    "raise" (OSError launch failure). Concurrency is tracked under a lock
    so the queue model can assert slot bounds deterministically.
    """

    def __init__(self, fail=None):
        self.fail = dict(fail or {})
        self.calls: list[list[str]] = []
        self.lock = threading.Lock()
        self.current = 0
        self.peak = 0

    def _device_of(self, argv: list[str]) -> str | None:
        if "--device-key" in argv:
            return argv[argv.index("--device-key") + 1]
        return None

    def __call__(self, argv: list[str], env: dict):
        assert env.get("LIFIO_CAPTURE_LEASE") == "1", \
            "worker must pass the lease to every child"
        with self.lock:
            self.current += 1
            self.peak = max(self.peak, self.current)
            self.calls.append(list(argv))
        try:
            device = self._device_of(argv)
            mode = self.fail.get(device)
            if mode == "raise":
                raise OSError("injected launch failure")
            if mode == "rc" and argv[2:3] == ["run-session"]:
                return SimpleNamespace(returncode=1, stdout="",
                                       stderr="injected session failure")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        finally:
            with self.lock:
                self.current -= 1

    def session_calls(self):
        """(run_id, domain, device_key) per run-session invocation."""
        out = []
        for argv in self.calls:
            if argv[2:3] == ["run-session"]:
                run_id = argv[argv.index("--run-id") + 1]
                domain = argv[argv.index("--domain") + 1]
                key = argv[argv.index("--device-key") + 1]
                out.append((run_id, domain, key))
        return out

    def work_keys(self):
        """(device, locale, pass, domain) per run-session invocation.

        Run ids carry the worker's fresh invocation namespace
        (<device>-<locale>-r1-<invocation>, §9), so exact-once is
        compared on the structural key — while the raw run ids must
        still be namespaced and distinct per device (see below).
        """
        keys = []
        for run_id, domain, key in self.session_calls():
            work_key, _inv = parse_work_call(run_id, domain, key)
            assert work_key[1] in LOCALES, run_id
            keys.append(work_key)
        return sorted(keys)

    def invocation_ids(self):
        """Raw invocation namespace per run-session call (freshness)."""
        return [parse_work_call(run_id, domain, key)[1]
                for run_id, domain, key in self.session_calls()]

    def assert_no_sim_or_build(self, testcase):
        bad = [argv for argv in self.calls
               if any("simctl" in a or "xcodebuild" in a for a in argv)]
        testcase.assertEqual(bad, [])


def expected_work(devices, locales=LOCALES):
    """Every (device, locale, pass, domain) the real worker must invoke
    once (structural key: run ids additionally carry the fresh
    invocation namespace, asserted separately)."""
    return sorted(
        (dev, loc, p, dom)
        for dev in devices for loc in locales for p in PASSES
        for dom in DOMAINS)


_RUN_ID_RE = re.compile(r"^([A-Za-z0-9]+)-(.+)-r1-([A-Za-z0-9_-]+)$")


def parse_work_call(run_id: str, domain: str, key: str
                    ) -> tuple[tuple[str, str, str, str], str]:
    """Split a worker run-session call into ((device, locale, pass,
    domain), invocation). Single-pass run ids are
    <device>-<locale>-r1-<invocation>; anything else fails loudly."""
    match = _RUN_ID_RE.match(run_id)
    assert match, f"run id not in single-pass form: {run_id!r}"
    dev, locale, inv = match.groups()
    assert dev == key, (run_id, key)
    return (dev, locale, "r1", domain), inv


def verify_all_executed(selected: list[str], session_calls) -> list[str]:
    """Completeness oracle: devices with zero executed domains."""
    executed = {key for _, _, key in session_calls}
    return [dev for dev in selected if dev not in executed]


class FakeCIQueue:
    """Deterministic UNIT model of a bounded CI slot pool.

    Jobs are submitted in selection order (queued ledger). Threaded mode
    overlaps them through Semaphore(capacity); a lock-appended event
    ledger records every queued/started/completed transition, and the
    test audits that ledger for the slot bound (running count derived
    from the total event order never exceeds capacity and returns to
    zero) plus retention (every queued job started+completed exactly
    once). No sleeps anywhere; thread joins time out loudly instead of
    hanging. Serial mode steps the same queue one job at a time
    (explicit unit semantics for the cancel case); bounds still apply.

    Deliberately NOT proven here: simultaneity/overlap peaks (any
    interleaving, serial included, is valid local behavior) and anything
    about real waiting time, contention, or competitor visibility.
    """

    def __init__(self, capacity: int):
        assert capacity >= 1
        self.capacity = capacity
        self.slot = threading.Semaphore(capacity)
        self.lock = threading.Lock()
        self.events: list[tuple] = []

    def _note(self, event: tuple):
        with self.lock:
            self.events.append(event)

    def audit_bounds(self, testcase):
        """Replay the ledger: running count stays within [0, capacity]."""
        running = 0
        peak = 0
        for event in self.events:
            if event[0] == "started":
                running += 1
                peak = max(peak, running)
            elif event[0] == "completed":
                running -= 1
            testcase.assertGreaterEqual(running, 0)
            testcase.assertLessEqual(running, self.capacity)
        testcase.assertEqual(running, 0)

    def run_all(self, jobs, serial: bool = False):
        """jobs: [(device, thunk)] in selection order. Returns events."""
        for device, _thunk in jobs:
            self._note(("queued", device))
        if serial:
            for device, thunk in jobs:
                with self.slot:
                    self._note(("started", device))
                    try:
                        result = thunk()
                    except Exception as exc:  # loud, never silent
                        self._note(("thread-error", device, repr(exc)))
                        result = None
                    self._note(("completed", device, result))
            return list(self.events)
        threads = []
        for device, thunk in jobs:
            thread = threading.Thread(target=self._worker, args=(device,
                                                                 thunk),
                                      daemon=True)
            threads.append(thread)
            thread.start()
        for thread in threads:
            thread.join(timeout=THREAD_TIMEOUT)
            if thread.is_alive():
                self._note(("thread-hung", thread.name))
        return list(self.events)

    def _worker(self, device, thunk):
        try:
            with self.slot:
                self._note(("started", device))
                try:
                    result = thunk()
                except Exception as exc:  # loud, never silent
                    self._note(("thread-error", device, repr(exc)))
                    result = None
                self._note(("completed", device, result))
        except Exception as exc:  # e.g. lock failure: loud, never silent
            self._note(("thread-error", device, repr(exc)))


class OversubscribedWorkflowTests(SixDeviceCatalog):
    maxDiff = None

    def _worker_kwargs(self, tmp: str, out: str = "shots"):
        return {
            "out_dir": Path(tmp) / out,
            "capture_py": HERE / "capture.py",
            "env": {"LIFIO_CAPTURE_LEASE": "1", "PATH": "/usr/bin:/bin"},
        }

    def _execute_device(self, tmp, backend, device, out="shots"):
        kw = self._worker_kwargs(tmp, out)
        return rw.execute(device_key=device,
                          device_udid=f"UDID-{device}", locales=list(LOCALES),
                          run=backend, **kw)

    def test_selection_returns_six_unique_ordered(self):
        sel = wi.validate_selection(json.dumps(SIX_DEVICES),
                                    json.dumps(LOCALES), "iOS 27.0")
        self.assertEqual(sel["devices"], SIX_DEVICES)
        self.assertEqual(sel["worker_count"], 6)
        self.assertEqual(len(set(sel["devices"])), 6)

    def test_local_sequential_capacity_pinned(self):
        # The local driver is strictly sequential (one simulator at a
        # time, owner decision) — capacity is the local constant.
        self.assertEqual(local_max_parallel(), 1)

    def _threaded_success(self, slots: int):
        ceiling = local_max_parallel()
        capacity = min(slots, ceiling)
        with tempfile.TemporaryDirectory() as tmp:
            backend = FakeBackend()
            queue = FakeCIQueue(capacity)
            jobs = [(dev, lambda dev=dev: self._execute_device(
                tmp, backend, dev)) for dev in SIX_DEVICES]
            events = queue.run_all(jobs)
            self.assertFalse(
                [e for e in events if e[0] in ("thread-error",
                                               "thread-hung")], events)
            started = [e[1] for e in events if e[0] == "started"]
            completed = {e[1]: e[2] for e in events if e[0] == "completed"}
            # Bounds from the ledger replay (never above capacity,
            # back to zero): queued work waited for slots, it was not
            # dropped to fit them. Overlap peaks are NOT asserted: any
            # interleaving, serial included, is valid local behavior.
            queue.audit_bounds(self)
            # No drop: every selected device started and completed once.
            self.assertEqual(sorted(started), sorted(SIX_DEVICES))
            self.assertEqual(sorted(completed), sorted(SIX_DEVICES))
            for dev in SIX_DEVICES:
                code, summary = completed[dev]
                self.assertEqual(code, 0, (dev, summary.get("error")))
                self.assertTrue(summary["effective_complete"], dev)
            # Exact-once work from the REAL worker path (not a scheduler
            # echo): every pair/pass/domain invoked once, nothing else
            # (single pass: 6 devices × 1 locale × 1 pass × 2 domains
            # = 12 session calls).
            self.assertEqual(backend.work_keys(),
                             expected_work(SIX_DEVICES))
            self.assertEqual(len(backend.session_calls()), 12)
            # Fresh run identity: every device worker minted its own
            # invocation namespace (no shared/hardcoded run ids).
            self.assertEqual(len(set(backend.invocation_ids())), 6)
            self.assertEqual(verify_all_executed(
                SIX_DEVICES, backend.session_calls()), [])
            backend.assert_no_sim_or_build(self)
            return backend, queue

    def test_six_devices_two_slots_all_execute_once(self):
        self._threaded_success(slots=2)

    def test_six_devices_three_slots_all_execute_once(self):
        self._threaded_success(slots=3)

    def test_failed_device_does_not_drop_later(self):
        ceiling = local_max_parallel()
        with tempfile.TemporaryDirectory() as tmp:
            backend = FakeBackend(fail={SIX_DEVICES[3]: "rc"})
            queue = FakeCIQueue(min(2, ceiling))
            jobs = [(dev, lambda dev=dev: self._execute_device(
                tmp, backend, dev)) for dev in SIX_DEVICES]
            events = queue.run_all(jobs)
            self.assertFalse(
                [e for e in events if e[0] in ("thread-error",
                                               "thread-hung")], events)
            completed = {e[1]: e[2] for e in events if e[0] == "completed"}
            self.assertEqual(sorted(completed), sorted(SIX_DEVICES))
            # The failed device reports failure with its own status...
            code, summary = completed[SIX_DEVICES[3]]
            self.assertEqual(code, 1)
            self.assertFalse(summary["effective_complete"])
            # ...earlier work is preserved...
            for dev in SIX_DEVICES[:3]:
                self.assertEqual(completed[dev][0], 0, dev)
                self.assertTrue(completed[dev][1]["effective_complete"], dev)
            # ...and LATER queued devices still executed fully (no drop).
            for dev in SIX_DEVICES[4:]:
                self.assertEqual(completed[dev][0], 0, dev)
                self.assertTrue(completed[dev][1]["effective_complete"], dev)
            # The failed device ran its work until its own failure; every
            # other device ran its complete pair/pass/domain set exactly.
            for dev in SIX_DEVICES:
                if dev == SIX_DEVICES[3]:
                    continue
                dev_calls = [c for c in backend.session_calls()
                             if c[2] == dev]
                dev_keys = [parse_work_call(run_id, domain, key)[0]
                            for run_id, domain, key in dev_calls]
                self.assertEqual(
                    sorted(dev_keys),
                    sorted(expected_work([dev])), dev)
            backend.assert_no_sim_or_build(self)

    def test_cancel_file_precreated_leaves_explicit_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            backend = FakeBackend()
            cancel = Path(tmp) / "cancel"
            cancel.write_text("cancel", encoding="utf-8")
            out = Path(tmp) / "shots"
            summaries = {}
            for dev in SIX_DEVICES:
                kw = self._worker_kwargs(tmp)
                code, summary = rw.execute(
                    device_key=dev, device_udid=f"UDID-{dev}",
                    locales=list(LOCALES), run=backend,
                    cancel_file=str(cancel), **kw)
                summaries[dev] = (code, summary)
            # Cancelled before any child ran: explicit unattempted records
            # everywhere, zero subprocess calls, nothing silently skipped.
            self.assertEqual(backend.calls, [])
            for dev in SIX_DEVICES:
                code, summary = summaries[dev]
                self.assertEqual(code, 4, dev)
                self.assertTrue(summary["cancelled"], dev)
                for loc in LOCALES:
                    for p in PASSES:
                        rec = wa.load_status(
                            out / dev / loc / f"{dev}-{loc}-{p}.status.json")
                        self.assertEqual(
                            rec["status"], wa.STATUS_UNATTEMPTED, rec)

    def test_cancel_midrun_serial_keeps_completed_stops_rest(self):
        # Serial stepping of the same queue semantics (explicit unit
        # semantics, deterministic): cancel lands after device 1, so its
        # work is preserved and every later device is explicitly
        # unattempted with no further child calls.
        with tempfile.TemporaryDirectory() as tmp:
            backend = FakeBackend()
            queue = FakeCIQueue(2)
            cancel = Path(tmp) / "cancel"
            out = Path(tmp) / "shots"
            first = SIX_DEVICES[0]
            kw = self._worker_kwargs(tmp)
            code, first_summary = rw.execute(
                device_key=first, device_udid=f"UDID-{first}",
                locales=list(LOCALES), run=backend, **kw)
            self.assertEqual(code, 0)
            calls_after_first = len(backend.calls)
            self.assertGreater(calls_after_first, 0)
            cancel.write_text("cancel", encoding="utf-8")
            rest_events = queue.run_all(
                [(dev, lambda dev=dev: rw.execute(
                    device_key=dev, device_udid=f"UDID-{dev}",
                    locales=list(LOCALES), run=backend,
                    cancel_file=str(cancel), **self._worker_kwargs(tmp)))
                 for dev in SIX_DEVICES[1:]], serial=True)
            # No child ran after the cancel landed.
            self.assertEqual(len(backend.calls), calls_after_first)
            started = [e[1] for e in rest_events if e[0] == "started"]
            self.assertEqual(sorted(started), sorted(SIX_DEVICES[1:]))
            for dev in SIX_DEVICES[1:]:
                code, summary = dict(
                    (e[1], e[2]) for e in rest_events
                    if e[0] == "completed")[dev]
                self.assertEqual(code, 4, dev)
                self.assertTrue(summary["cancelled"], dev)
            # Device 1's completed pairs are preserved on disk.
            for loc in LOCALES:
                for p in PASSES:
                    rec = wa.load_status(
                        out / first / loc / f"{first}-{loc}-{p}.status.json")
                    self.assertEqual(rec["status"], wa.STATUS_OK, rec)

    def test_truncation_mutation_detected(self):
        # Red oracle: had selection silently shrunk the
        # six-device input to five, the completeness check below — the
        # same check the success tests apply to real worker output —
        # reports exactly the dropped device. This test passing proves
        # the invariant bites; it does not claim a real bug existed.
        sel = wi.validate_selection(json.dumps(SIX_DEVICES),
                                    json.dumps(LOCALES), "iOS 27.0")
        mutated = list(sel["devices"])[:5]
        with tempfile.TemporaryDirectory() as tmp:
            backend = FakeBackend()
            queue = FakeCIQueue(2)
            jobs = [(dev, lambda dev=dev: self._execute_device(
                tmp, backend, dev)) for dev in mutated]
            queue.run_all(jobs)
            missing = verify_all_executed(
                SIX_DEVICES, backend.session_calls())
            self.assertEqual(missing, [SIX_DEVICES[5]])


if __name__ == "__main__":
    unittest.main(verbosity=2)
