#!/usr/bin/env python3
"""Session protocol regression tests (frozen v2 envelope, evidence/protocol.md).

Tests-first contract for scripts/screenshots/session.py (tasks 2.2-2.4):
raw request_json-string SHA, nonce/seq/identity binding, atomic
consume-before-execute with replay-vs-reobserve, immutable session inputs,
semantic r1/r2 hashes, timings without cross-clock math. No device, tmp only.
"""

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import request_schema as rs
import session as sess

FIXTURE = HERE / "tests" / "fixtures" / "session_envelope_golden.json"

NONCE_A = "0123456789abcdef0123456789abcdef"
NONCE_B = "fedcba9876543210fedcba9876543210"


def base_payload(run_id="sess-r1"):
    base = json.loads((HERE / "pilot_manifest.json").read_text(encoding="utf-8"))
    base = {k: v for k, v in base.items() if k not in ("frame", "mode")}
    base["run_id"] = run_id
    return base


def payload_for(frame, run_id="sess-r1"):
    p = rs.build_frame_request(base_payload(run_id), frame)
    assert rs.validate_request_dict(p) == []
    return p


def envelope_for(frame, nonce=NONCE_A, domain="pinned", seq=0, run_id="sess-r1"):
    return sess.build_envelope(
        payload_for(frame, run_id),
        run_id=run_id, session_nonce=nonce, session_domain=domain, seq=seq,
    )


class GoldenVectorTests(unittest.TestCase):
    def test_golden_vectors_reproduce_exactly(self):
        fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(len(fixture["vectors"]), 2)
        for vec in fixture["vectors"]:
            env = vec["envelope"]
            inner = json.loads(env["request_json"])
            rebuilt = sess.build_envelope(
                inner, run_id=env["run_id"], session_nonce=env["session_nonce"],
                session_domain=env["session_domain"], seq=env["seq"],
            )
            self.assertEqual(rebuilt, env, vec["name"])

    def test_sha_is_over_raw_utf8_string_never_reserialized(self):
        fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        for vec in fixture["vectors"]:
            env = vec["envelope"]
            raw_utf8 = env["request_json"].encode("utf-8")
            self.assertEqual(hashlib.sha256(raw_utf8).hexdigest(),
                             env["request_sha256"], vec["name"])
            # The raw string ends with the canonical trailing newline.
            self.assertTrue(env["request_json"].endswith("\n"))
            # Re-serializing the parsed payload yields identical bytes
            # (canonical form), but the SHA under contract is over the
            # transmitted string, not over a re-encode.
            inner = json.loads(env["request_json"])
            self.assertEqual(rs.canonical_bytes(inner), raw_utf8)
            self.assertEqual(sess.semantic_sha256_of_payload(inner),
                             vec["request_semantic_sha256"])

    def test_outer_metadata_change_does_not_change_payload_sha(self):
        env_a = envelope_for("track-running", nonce=NONCE_A, seq=0)
        env_b = envelope_for("track-running", nonce=NONCE_B, seq=3,
                             run_id="sess-r1")
        # Same frame payload except run_id is stable here; nonce/seq live
        # in the envelope only, so the payload SHA is unaffected by them.
        # (run_id is payload-volatile by design; see semantic tests.)
        same_run = sess.build_envelope(
            payload_for("track-running", "sess-r1"), run_id="sess-r1",
            session_nonce=NONCE_B, session_domain="pinned", seq=3)
        self.assertEqual(same_run["request_sha256"], env_a["request_sha256"])
        self.assertNotEqual(env_a["session_nonce"], env_b["session_nonce"])


class EnvelopeValidationTests(unittest.TestCase):
    def test_arbitrary_json_never_raises(self):
        for probe in (None, [], "x", 42, True, {"schema_version": 2},
                      {"schema_version": 1, "request_json": "{}"},
                      {"schema_version": 2, "seq": "0"}):
            self.assertIsInstance(sess.validate_envelope(probe), list)

    def test_legacy_v1_payload_without_envelope_rejected(self):
        raw_v1 = payload_for("track-running")
        self.assertTrue(sess.validate_envelope(raw_v1))
        self.assertTrue(any("schema_version" in e
                            for e in sess.validate_envelope(raw_v1)))

    def test_bad_nonce_rejected(self):
        for bad in ("", "UPPERCASE0123456789ABCDEF01234567", "short",
                    "0123456789abcdef0123456789abcde!", "../" + "a" * 28,
                    "/absolute/path/0123456789abcdef", "a" * 31, "a" * 33,
                    "0123456789abcdef0123456789abcde "):
            with self.subTest(nonce=bad[:20]):
                with self.assertRaises(sess.SessionError):
                    sess.build_envelope(payload_for("track-running"),
                                        run_id="sess-r1", session_nonce=bad,
                                        session_domain="pinned", seq=0)

    def test_bad_domain_and_seq_rejected(self):
        for domain in ("", "pinned-realtime", "PINNED", None):
            with self.assertRaises(sess.SessionError):
                sess.build_envelope(payload_for("track-running"),
                                    run_id="sess-r1", session_nonce=NONCE_A,
                                    session_domain=domain, seq=0)
        for seq in (-1, 1.5, "0", True, None):
            with self.assertRaises(sess.SessionError):
                sess.build_envelope(payload_for("track-running"),
                                    run_id="sess-r1", session_nonce=NONCE_A,
                                    session_domain="pinned", seq=seq)

    def test_cross_domain_frame_rejected(self):
        with self.assertRaises(sess.SessionError):
            sess.build_envelope(payload_for("la-lock"), run_id="sess-r1",
                                session_nonce=NONCE_A,
                                session_domain="pinned", seq=0)
        with self.assertRaises(sess.SessionError):
            sess.build_envelope(payload_for("track-running"), run_id="sess-r1",
                                session_nonce=NONCE_A,
                                session_domain="realtime", seq=0)

    def test_outer_inner_mismatch_rejected(self):
        env = envelope_for("track-running")
        env["frame"] = "insights"  # outer mutated, inner still track-running
        self.assertTrue(any("frame" in e for e in sess.validate_envelope(env)))
        env = envelope_for("track-running")
        env["run_id"] = "other-run"
        self.assertTrue(any("run_id" in e for e in sess.validate_envelope(env)))
        env = envelope_for("track-running")
        env["request_sha256"] = "0" * 64
        self.assertTrue(any("request_sha256" in e
                            for e in sess.validate_envelope(env)))

    def test_tampered_request_json_rejected(self):
        env = envelope_for("track-running")
        inner = json.loads(env["request_json"])
        inner["locale"] = "ru"
        env["request_json"] = json.dumps(inner, sort_keys=True) + "\n"
        errs = sess.validate_envelope(env)
        self.assertTrue(errs)


class TransitionTests(unittest.TestCase):
    def test_pinned_story_order_enforced(self):
        seqs = [envelope_for(f, seq=i)
                for i, f in enumerate(sess.PINNED_SESSION_FRAMES)]
        consumed: set[int] = set()
        prev = None
        for env in seqs:
            self.assertEqual(sess.validate_transition(prev, env, consumed), [])
            consumed.add(env["seq"])
            prev = env

    def test_realtime_story_order_enforced(self):
        seqs = [envelope_for(f, nonce=NONCE_B, domain="realtime", seq=i)
                for i, f in enumerate(sess.REALTIME_SESSION_FRAMES)]
        consumed: set[int] = set()
        prev = None
        for env in seqs:
            self.assertEqual(sess.validate_transition(prev, env, consumed), [])
            consumed.add(env["seq"])
            prev = env

    def test_skip_and_out_of_order_rejected(self):
        first = envelope_for("track-running", seq=0)
        third = envelope_for("history", seq=2)
        errs = sess.validate_transition(first, third, {0})
        self.assertTrue(errs)
        # Same seq twice is a replay, even with identical bytes.
        dup = envelope_for("track-running", seq=0)
        self.assertTrue(any("replay" in e.lower()
                            for e in sess.validate_transition(first, dup, {0})))

    def test_immutable_inputs_fixed_within_session(self):
        first = envelope_for("track-running", seq=0)
        other = dict(payload_for("insights"))
        other["locale"] = "ru"
        other["region"] = "RU"
        other["timezone"] = "Europe/Moscow"
        other["keyboard"] = {"language": "ru-RU", "software_visible": True,
                             "presentation": "docked"}
        changed = sess.build_envelope(other, run_id="sess-r1",
                                      session_nonce=NONCE_A,
                                      session_domain="pinned", seq=1)
        errs = sess.validate_transition(first, changed, {0})
        self.assertTrue(any("locale" in e for e in errs))

    def test_mode_change_within_domain_rejected(self):
        first = envelope_for("track-running", seq=0)
        # la-lock cannot even be built for the pinned domain; an attacker
        # hand-crafting the envelope still fails transition.
        raw = dict(envelope_for("track-running", seq=1))
        raw["frame"] = "la-lock"
        raw["mode"] = "live-activity-realtime"
        errs = sess.validate_transition(first, raw, {0})
        self.assertTrue(errs)


class QueueAtomicityTests(unittest.TestCase):
    def test_publish_claim_noop_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sessions"
            env0 = envelope_for("track-running", seq=0)
            qp = sess.publish_command(root, env0)
            self.assertTrue(qp.is_file())
            # One-in-flight: second publish while one is queued fails.
            with self.assertRaises(sess.SessionError):
                sess.publish_command(root, envelope_for("insights", seq=1))
            claimed = sess.claim_command(root, NONCE_A)
            self.assertEqual(claimed["seq"], 0)
            self.assertFalse(qp.exists())  # claimed BEFORE execution
            # Re-observing the retained consumed record is a no-op.
            self.assertIsNone(sess.claim_command(root, NONCE_A))
            self.assertEqual(sess.consumed_seqs(root, NONCE_A), {0})
            # ANY new publication with an old seq is a replay, even
            # byte-identical bytes.
            with self.assertRaises(sess.SessionError) as ctx:
                sess.publish_command(root, envelope_for("track-running",
                                                        seq=0))
            self.assertIn("replay", str(ctx.exception).lower())
            # Next expected seq publishes cleanly.
            sess.publish_command(root, envelope_for("insights", seq=1))
            self.assertEqual(sess.claim_command(root, NONCE_A)["seq"], 1)

    def test_partial_write_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sessions"
            d = root / NONCE_A
            d.mkdir(parents=True)
            (d / "command.json").write_bytes(b'{"schema_version": 2, "seq":')
            with self.assertRaises(sess.SessionError):
                sess.claim_command(root, NONCE_A)

    def test_traversal_and_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sessions"
            root.mkdir()
            with self.assertRaises(sess.SessionError):
                sess.queue_path_for(root, "../escape")
            with self.assertRaises(sess.SessionError):
                sess.queue_path_for(root, "a" * 32 + "/x")
            link = root / NONCE_A
            link.symlink_to(Path(tmp), target_is_directory=True)
            with self.assertRaises(sess.SessionError):
                sess.publish_command(root, envelope_for("track-running"))

    def test_end_of_session_then_stale_command_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sessions"
            sess.publish_command(root, envelope_for("track-running", seq=0))
            sess.claim_command(root, NONCE_A)
            sess.mark_session_ended(root, NONCE_A, final_seq=0)
            with self.assertRaises(sess.SessionError):
                sess.publish_command(root, envelope_for("insights", seq=1))


class SemanticHashTests(unittest.TestCase):
    def test_volatile_identities_do_not_change_semantic(self):
        a = payload_for("track-running", "run-a")
        b = payload_for("track-running", "run-b")
        self.assertEqual(sess.semantic_sha256_of_payload(a),
                         sess.semantic_sha256_of_payload(b))
        # Envelope-only identities never enter the payload projection.
        ea = envelope_for("track-running", nonce=NONCE_A, seq=0,
                          run_id="run-a")
        eb = envelope_for("track-running", nonce=NONCE_B, seq=5,
                          run_id="run-a")
        self.assertEqual(ea["request_sha256"], eb["request_sha256"])

    def test_semantic_inputs_still_detected(self):
        a = payload_for("track-running", "run-a")
        for mutate in ("locale", "deck_version", "reference_local_iso",
                       "frame", "treatment"):
            b = dict(payload_for("track-running", "run-a"))
            b[mutate] = "CHANGED"
            self.assertNotEqual(sess.semantic_sha256_of_payload(a),
                                sess.semantic_sha256_of_payload(b), mutate)
        geo = dict(payload_for("track-running", "run-a"))
        geo["geometry"] = {"width": 1, "height": 1}
        self.assertNotEqual(sess.semantic_sha256_of_payload(a),
                            sess.semantic_sha256_of_payload(geo))


class TimingsTests(unittest.TestCase):
    def test_monotonic_phases_and_counters(self):
        stats = sess.PhaseStats()
        stats.start("launch")
        stats.count("simctl_spawn")
        stats.count("simctl_spawn")
        stats.stop("launch")
        d = stats.to_dict()
        self.assertGreaterEqual(d["phases_ms"]["launch"], 0)
        self.assertEqual(d["counters"]["simctl_spawn"], 2)

    def test_no_cross_clock_subtraction(self):
        stats = sess.PhaseStats()
        stats.start("poll")
        stats.stop("poll")
        # App-side durations are recorded separately and never subtracted
        # from runner monotonic phases.
        stats.note_app_duration("seed_ms", 1234)
        d = stats.to_dict()
        self.assertEqual(d["app_durations_ms"]["seed_ms"], 1234)
        self.assertNotIn("seed_ms", d["phases_ms"])

    def test_no_sensitive_inputs_logged(self):
        stats = sess.PhaseStats()
        stats.start("export")
        stats.stop("export")
        blob = json.dumps(stats.to_dict())
        self.assertNotIn("request_json", blob)
        self.assertNotIn("expected_totals", blob)


class _TickClock:
    """Deterministic monotonic fake clock (fixed step per reading)."""

    def __init__(self, start=1000.0, step=0.01):
        self.t = start
        self.step = step

    def __call__(self):
        v = self.t
        self.t += self.step
        return v


class SpawnTrailTests(unittest.TestCase):
    def test_trail_caps_at_20_with_exact_truncation_count(self):
        clock = _TickClock()
        stats = sess.PhaseStats(clock=clock)
        for i in range(25):
            t0 = clock()
            t1 = clock()
            stats.note_spawn(category=f"cat-{i:02d}", outcome="ok",
                             t_start=t0, t_end=t1, rc=0)
        d = stats.to_dict()
        self.assertEqual(len(d["spawn_trail"]), 20)
        self.assertEqual(d["spawn_dropped"], 5)
        # FIFO: oldest rolled off, newest retained in order.
        self.assertEqual(d["spawn_trail"][0]["category"], "cat-05")
        self.assertEqual(d["spawn_trail"][-1]["category"], "cat-24")
        # Existing keys keep their meaning.
        self.assertIn("phases_ms", d)
        self.assertIn("counters", d)
        self.assertIn("app_durations_ms", d)

    def test_trail_records_phase_timing_outcome_and_rc(self):
        clock = _TickClock()
        stats = sess.PhaseStats(clock=clock)
        stats.start("export")
        t0 = clock()
        t1 = clock()
        entry = stats.note_spawn(category="ui-appearance-query",
                                 outcome="timeout",
                                 t_start=t0, t_end=t1, rc=None)
        stats.stop("export")
        self.assertEqual(entry["phase"], "export")
        self.assertEqual(entry["outcome"], "timeout")
        self.assertIsNone(entry["rc"])
        self.assertGreaterEqual(entry["duration_ms"], 0)
        self.assertGreaterEqual(entry["start_rel_ms"], 0)
        # Outside any phase the label is explicit, never blank.
        t0 = clock()
        entry2 = stats.note_spawn(category="launch-cleanup",
                                  outcome="oserror",
                                  t_start=t0, t_end=t0, rc=None)
        self.assertEqual(entry2["phase"], "unknown")

    def test_trail_rejects_raw_argv_and_sensitive_shape(self):
        import inspect
        params = set(inspect.signature(sess.PhaseStats.note_spawn).parameters)
        for banned in ("argv", "path", "nonce", "launch_args", "stderr",
                       "request_json", "command"):
            self.assertNotIn(banned, params, banned)
        stats = sess.PhaseStats(clock=_TickClock())
        with self.assertRaises(sess.SessionError):
            stats.note_spawn(category=["xcrun", "simctl"], outcome="ok",
                             t_start=1.0, t_end=2.0)
        with self.assertRaises(sess.SessionError):
            stats.note_spawn(category="", outcome="ok",
                             t_start=1.0, t_end=2.0)
        with self.assertRaises(sess.SessionError):
            stats.note_spawn(category="ui-appearance-query",
                             outcome="hang", t_start=1.0, t_end=2.0)
        with self.assertRaises(sess.SessionError):
            stats.note_spawn(category="ui-appearance-query", outcome="ok",
                             t_start=1.0, t_end=2.0, rc=True)
        t0 = 1000.0
        stats.note_spawn(category="ui-appearance-query", outcome="ok",
                         t_start=t0, t_end=t0 + 0.05, rc=0)
        blob = json.dumps(stats.to_dict())
        for banned in ("xcrun", "simctl", "UDID", "SCREENSHOT",
                       "request_json", "expected_totals", "stderr"):
            self.assertNotIn(banned, blob, banned)

    def test_trail_uses_runner_clock_only_never_app_clock(self):
        clock = _TickClock()
        stats = sess.PhaseStats(clock=clock)
        stats.note_app_duration("seed_ms", 1234)
        t0 = clock()
        t1 = clock()
        entry = stats.note_spawn(category="launch-capture", outcome="ok",
                                 t_start=t0, t_end=t1, rc=0)
        # One step (0.01s) elapsed on the runner clock: exact up to
        # float rounding, no cross-clock subtraction against the
        # opaque app duration.
        self.assertAlmostEqual(entry["duration_ms"], 10.0, places=6)
        d = stats.to_dict()
        self.assertEqual(d["app_durations_ms"]["seed_ms"], 1234)
        self.assertNotIn("seed_ms", d["phases_ms"])
        self.assertNotIn("seed", json.dumps(d["spawn_trail"]))

    def test_trail_clamps_clock_skew_to_zero(self):
        stats = sess.PhaseStats(clock=_TickClock())
        entry = stats.note_spawn(category="device-list", outcome="ok",
                                 t_start=2000.0, t_end=1999.0, rc=0)
        self.assertEqual(entry["duration_ms"], 0.0)
        entry2 = stats.note_spawn(category="device-list", outcome="ok",
                                  t_start=500.0, t_end=500.0, rc=0)
        self.assertEqual(entry2["start_rel_ms"], 0.0)


class CleanupTokenTests(unittest.TestCase):
    def test_cleanup_argv_carries_session_tokens(self):
        argv = sess.build_cleanup_argv("UDID-1", rs.SCREENSHOT_BID, "sess-r1",
                                       "a" * 64, session_nonce=NONCE_A,
                                       session_domain="pinned", final_seq=3)
        joined = " ".join(argv)
        self.assertIn("SCREENSHOT_CLEANUP=sess-r1", joined)
        self.assertIn("SCREENSHOT_CLEANUP_SHA=" + "a" * 64, joined)
        self.assertIn("SCREENSHOT_SESSION_NONCE=" + NONCE_A, joined)
        self.assertIn("SCREENSHOT_SESSION_DOMAIN=pinned", joined)
        self.assertIn("SCREENSHOT_FINAL_SEQ=3", joined)

    def test_cleanup_argv_rejects_bad_identity(self):
        with self.assertRaises(sess.SessionError):
            sess.build_cleanup_argv("UDID-1", rs.SCREENSHOT_BID, "sess-r1",
                                    "a" * 64, session_nonce="bad",
                                    session_domain="pinned", final_seq=3)


class DomainFrameTests(unittest.TestCase):
    def test_frames_for_domain(self):
        self.assertEqual(sess.frames_for_domain("pinned"),
                         ["track-running", "insights", "history", "add-entry"])
        self.assertEqual(sess.frames_for_domain("realtime"),
                         ["la-lock", "la-compact", "la-expanded"])
        # iPad has no Dynamic Island: realtime session carries only the
        # Lock Screen frame; N/A probe evidence is separate (no sessions).
        self.assertEqual(sess.frames_for_domain("realtime",
                                                island_available=False),
                         ["la-lock"])
        with self.assertRaises(sess.SessionError):
            sess.frames_for_domain("prime-time")


PINNED_TOTALS = {"all_seconds": 1000, "today_seconds": 100,
                 "week_seconds": 500, "category_seconds": {"Work": 500},
                 "text_seconds": {"Gym": 100}}


def session_ack(env, status="ready", extra=None):
    inner = json.loads(env["request_json"])
    ack = {
        "schema_version": 2,
        "status": status,
        "session_nonce": env["session_nonce"],
        "run_id": env["run_id"],
        "session_domain": env["session_domain"],
        "seq": env["seq"],
        "frame": env["frame"],
        "mode": env["mode"],
        "request_sha256": env["request_sha256"],
        "deck_version": "en-austin-1",
        "counts": {"entries": 55},
        "expected_totals": dict(inner["expected_totals"]),
        "build": {"configuration": "Screenshot",
                  "bundle_id": rs.SCREENSHOT_BID},
        "transcript": [sess.transcript_entry(env)],
    }
    if extra:
        ack.update(extra)
    return ack


class SessionAckTests(unittest.TestCase):
    def test_ready_ack_binds_and_passes(self):
        import state_check as sc

        with tempfile.TemporaryDirectory() as tmp:
            pin_path = Path(tmp) / "pin.json"
            pin_path.write_text(json.dumps(
                rs.load_pinned_totals_for_locale("en")), encoding="utf-8")
            pin = sc.load_pinned_totals(str(pin_path))
            env = sess.build_envelope(
                payload_for("track-running"), run_id="sess-r1",
                session_nonce=NONCE_A, session_domain="pinned", seq=0)
            verdict, errs = sc.validate_session_ack(
                session_ack(env), env, pin)
            self.assertEqual((verdict, errs), (sc.OK, []))

    def test_preparing_is_pending_with_identity_bound(self):
        import state_check as sc

        env = envelope_for("track-running")
        verdict, _ = sc.validate_session_ack(
            session_ack(env, status="preparing"), env, dict(PINNED_TOTALS))
        self.assertEqual(verdict, sc.PENDING)

    def test_stale_ack_rejected(self):
        import state_check as sc

        env = envelope_for("track-running")
        ack = session_ack(env)
        ack["seq"] = 7  # stale/future ack for another command
        verdict, errs = sc.validate_session_ack(ack, env, dict(PINNED_TOTALS))
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("seq" in e for e in errs))

    def test_missing_transcript_rejected(self):
        import state_check as sc

        env = envelope_for("track-running")
        ack = session_ack(env)
        del ack["transcript"]
        verdict, errs = sc.validate_session_ack(ack, env, dict(PINNED_TOTALS))
        self.assertEqual(verdict, sc.FAILED)
        self.assertTrue(any("transcript" in e for e in errs))

    def test_v1_state_without_session_identity_rejected(self):
        import state_check as sc

        env = envelope_for("track-running")
        digest = env["request_sha256"]
        v1 = {"status": "ready", "request_sha256": digest,
              "deck_version": "en-austin-1", "frame": "track-running",
              "counts": {"entries": 55},
              "expected_totals": dict(PINNED_TOTALS),
              "build": {"configuration": "Screenshot",
                        "bundle_id": rs.SCREENSHOT_BID}}
        verdict, _ = sc.validate_session_ack(v1, env, dict(PINNED_TOTALS))
        self.assertEqual(verdict, sc.FAILED)

    def test_unsupported_schema_rejected_even_when_bindings_hold(self):
        import state_check as sc

        env = envelope_for("track-running")
        for bad_schema in (999, 1, "2", True, None):
            with self.subTest(schema=bad_schema):
                ack = session_ack(env)
                if bad_schema is None:
                    del ack["schema_version"]
                else:
                    ack["schema_version"] = bad_schema
                verdict, errs = sc.validate_session_ack(
                    ack, env, dict(PINNED_TOTALS))
                self.assertEqual(verdict, sc.FAILED, bad_schema)
                self.assertTrue(any("schema_version" in e for e in errs),
                                (bad_schema, errs))
        # Preparing with a bad schema is not pending: schema fail-closed
        # precedes pending truthfulness.
        ack = session_ack(env, status="preparing")
        ack["schema_version"] = 999
        verdict, _ = sc.validate_session_ack(ack, env, dict(PINNED_TOTALS))
        self.assertEqual(verdict, sc.FAILED)

    def test_malformed_non_object_ack_rejected(self):
        import state_check as sc

        env = envelope_for("track-running")
        for bad in (None, [], "ready", 42, True):
            with self.subTest(state=repr(bad)[:20]):
                verdict, errs = sc.validate_session_ack(
                    bad, env, dict(PINNED_TOTALS))
                self.assertEqual(verdict, sc.FAILED)
                self.assertTrue(errs)


class MirrorFixtureTests(unittest.TestCase):
    def test_swift_mirror_byte_identical_to_source(self):
        # The Swift golden file is a verbatim copy of the source fixture;
        # any drift (bytes or SHA) fails here so both owners re-sync.
        # Paths resolve from __file__ (repo-relative), robust to any
        # working directory. The mirror is read-only here (Swift-owned).
        import hashlib

        src = HERE / "tests" / "fixtures" / "session_envelope_golden.json"
        repo = HERE.parent.parent
        mirror = (repo / "ios" / "TimeOfLife" / "TimeOfLifeTests"
                  / "session_envelope_golden.json")
        self.assertTrue(src.is_file(), src)
        self.assertTrue(mirror.is_file(),
                        f"Swift mirror missing: {mirror}")
        src_raw = src.read_bytes()
        mirror_raw = mirror.read_bytes()
        self.assertEqual(hashlib.sha256(src_raw).hexdigest(),
                         hashlib.sha256(mirror_raw).hexdigest(),
                         "golden fixture drift between source and mirror")
        self.assertEqual(src_raw, mirror_raw)
        fixture = json.loads(src_raw.decode("utf-8"))
        self.assertEqual(len(fixture["vectors"]), 2)
        for vec in fixture["vectors"]:
            self.assertEqual(
                sorted(vec["envelope"]),
                sorted(fixture["contract"]["envelope_keys"]))


class ModelCatalogTests(unittest.TestCase):
    P = "com.apple.CoreSimulator.SimDeviceType."

    def test_host_verified_identifiers(self):
        # Exact host strings (read-only simctl list -j devicetypes,
        # Xcode 27.1: iPhone 17 Pro Max / iPhone 17 / M5 12GB+16GB).
        self.assertTrue(sess.island_for_model(self.P + "iPhone-17-Pro-Max"))
        self.assertTrue(sess.island_for_model(self.P + "iPhone-17-Pro"))
        self.assertTrue(sess.island_for_model(self.P + "iPhone-17"))
        self.assertTrue(sess.island_for_model("iPhone-Air"))
        self.assertFalse(sess.island_for_model(
            self.P + "iPad-Pro-13-inch-M5-12GB"))
        self.assertFalse(sess.island_for_model(self.P + "iPhone-16e"))
        self.assertFalse(sess.island_for_model(
            self.P + "iPhone-SE--2nd-generation-"))

    def test_phantom_and_future_models_fail_closed(self):
        cases = ["iPhone-17-Air", "iPhone-Duo", "iPhone-17e",
                 "iPhone-11-Pro-Max", "Apple-TV-4K", "", "../x"]
        for bad in cases:
            with self.subTest(model=bad):
                with self.assertRaises(sess.SessionError):
                    sess.island_for_model(self.P + bad)
        with self.assertRaises(sess.SessionError):
            sess.island_for_model(None)

    def test_catalog_model_exact_proof(self):
        ipad = self.P + "iPad-Pro-13-inch-M5-12GB"
        self.assertEqual(
            sess.check_catalog_model("ipad13", ipad, "shot-ci-ipad13"), [])
        self.assertEqual(
            sess.check_catalog_model(
                "ipad13", "iPad-Pro-13-inch-M5-12GB", "shot-ci-ipad13"), [])
        # Second M5 memory variant also attests ipad13.
        ipad16 = self.P + "iPad-Pro-13-inch-M5-16GB"
        self.assertEqual(
            sess.check_catalog_model("ipad13", ipad16, "shot-ci-ipad13"), [])
        # Retired M4 models cannot attest the new ipad13 matrix entry
        # (no legacy branches, no aliases).
        self.assertTrue(sess.check_catalog_model(
            "ipad13", self.P + "iPad-Pro-13-inch-M4-8GB", "shot-ci-ipad13"))
        self.assertTrue(sess.check_catalog_model(
            "ipad13", self.P + "iPad-Pro-13-inch-M4-16GB", "shot-ci-ipad13"))
        # Retired 18 Pro Max cannot attest the new iphone69 entry.
        self.assertTrue(sess.check_catalog_model(
            "iphone69", self.P + "iPhone-18-Pro-Max", "shot-ci-iphone69"))
        # Current 17 Pro Max attests iphone69; 17 attests iphone63.
        self.assertEqual(sess.check_catalog_model(
            "iphone69", self.P + "iPhone-17-Pro-Max", "shot-ci-iphone69"), [])
        self.assertEqual(sess.check_catalog_model(
            "iphone63", self.P + "iPhone-17", "shot-ci-iphone63"), [])
        # Different iPad model, same geometry: cannot attest ipad13.
        air = self.P + "iPad-Air-11-inch-M4"
        self.assertTrue(sess.check_catalog_model(
            "ipad13", air, "shot-ci-ipad13"))
        # Phantom model: prefix alone never suffices.
        self.assertTrue(sess.check_catalog_model(
            "ipad13", "iPad-13-inch-M3", "shot-ci-ipad13"))
        # Wrong key, unknown key, bad name.
        self.assertTrue(sess.check_catalog_model(
            "iphone69", ipad, "shot-ci-ipad13"))
        self.assertTrue(sess.check_catalog_model(
            "gameboy", ipad, "shot-ci-ipad13"))
        self.assertTrue(sess.check_catalog_model("ipad13", ipad, ""))
        self.assertTrue(sess.check_catalog_model("ipad13", ipad, "../x"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
