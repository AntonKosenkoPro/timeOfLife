#!/usr/bin/env python3
"""Focused tests for apply-opencode-model-routing.py.

Covers: idempotence, recovery after `openspec update` wipes pins,
and preservation of body/description/unrelated files.

Run: python3 scripts/test_apply_opencode_model_routing.py
"""

import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "apply-opencode-model-routing.py"

# Load the script as a module without executing main().
import importlib.util

spec = importlib.util.spec_from_file_location("apply_routing", SCRIPT)
apply_routing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apply_routing)


def write_cmd(dirpath: Path, name: str, text: str) -> Path:
    p = dirpath / f"{name}.md"
    p.write_text(text)
    return p


SAMPLE_APPLY_WIPED = """---
description: "Implement tasks from an OpenSpec change (Experimental)"
---

Implement tasks from an OpenSpec change.
"""

SAMPLE_APPLY_PINNED = """---
model: openai/gpt-6.1-sol#medium
description: "Implement tasks from an OpenSpec change (Experimental)"
---
> Model routing: orchestrator runs on `openai/gpt-6.1-sol#medium`.
> Delegate ALL code edits, repros, and test/verify runs to the
> `lifio-implementer` subagent (`opencode-go/muse-spark-1.3-contributor#xhigh`)
> via the subagent tool. Do not implement or run tests in the orchestrator session.

Implement tasks from an OpenSpec change.
"""


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cmds = Path(self.tmp.name)
        self._orig = apply_routing.COMMANDS
        apply_routing.COMMANDS = self.cmds

    def tearDown(self):
        apply_routing.COMMANDS = self._orig
        self.tmp.cleanup()

    def test_routing_table(self):
        self.assertEqual(
            apply_routing.ROUTING,
            {
                "opsx-explore": "openai/gpt-6.1-sol#high",
                "opsx-propose": "openai/gpt-6.1-sol#high",
                "opsx-apply": "openai/gpt-6.1-sol#medium",
                "opsx-archive": "openai/gpt-6.1-sol#medium",
                "opsx-pr": "openai/gpt-6.1-sol#medium",
            },
        )

    def test_recovery_restores_wiped_pin(self):
        """Simulates `openspec update` wiping model+note: script restores both."""
        write_cmd(self.cmds, "opsx-apply", SAMPLE_APPLY_WIPED)
        status = apply_routing.apply_pin(
            "opsx-apply", apply_routing.ROUTING["opsx-apply"]
        )
        self.assertEqual(status, "updated")
        out = (self.cmds / "opsx-apply.md").read_text()
        self.assertIn("model: openai/gpt-6.1-sol#medium", out)
        self.assertIn("lifio-implementer", out)
        self.assertIn("Implement tasks from an OpenSpec change.", out)

    def test_idempotent_second_run(self):
        write_cmd(self.cmds, "opsx-apply", SAMPLE_APPLY_WIPED)
        first = apply_routing.apply_pin(
            "opsx-apply", apply_routing.ROUTING["opsx-apply"]
        )
        before = (self.cmds / "opsx-apply.md").read_text()
        second = apply_routing.apply_pin(
            "opsx-apply", apply_routing.ROUTING["opsx-apply"]
        )
        after = (self.cmds / "opsx-apply.md").read_text()
        self.assertEqual(first, "updated")
        self.assertEqual(second, "ok")
        self.assertEqual(before, after)

    def test_preserves_description_body_and_newline(self):
        write_cmd(self.cmds, "opsx-apply", SAMPLE_APPLY_PINNED)
        status = apply_routing.apply_pin(
            "opsx-apply", apply_routing.ROUTING["opsx-apply"]
        )
        self.assertEqual(status, "ok")
        out = (self.cmds / "opsx-apply.md").read_text()
        self.assertIn(
            'description: "Implement tasks from an OpenSpec change (Experimental)"',
            out,
        )
        self.assertTrue(out.endswith("\n"))
        # model appears exactly once, at top of frontmatter
        self.assertEqual(out.count("model:"), 1)
        self.assertTrue(out.startswith("---\nmodel: "))

    def test_pr_note_enforced(self):
        wiped = (
            "---\n"
            'description: "Process a PR after implementation — template PR, green CI, AI-review loop, human handoff (never merge)"\n'
            "---\n"
            "\n"
            "Take an implemented branch to **human-review-ready**.\n"
        )
        write_cmd(self.cmds, "opsx-pr", wiped)
        status = apply_routing.apply_pin(
            "opsx-pr", apply_routing.ROUTING["opsx-pr"]
        )
        self.assertEqual(status, "updated")
        out = (self.cmds / "opsx-pr.md").read_text()
        self.assertIn("model: openai/gpt-6.1-sol#medium", out)
        self.assertIn("lifio-implementer", out)

    def test_missing_frontmatter_raises(self):
        write_cmd(self.cmds, "opsx-apply", "no frontmatter here\n")
        with self.assertRaises(ValueError):
            apply_routing.apply_pin(
                "opsx-apply", apply_routing.ROUTING["opsx-apply"]
            )


class ConfigShapeTests(unittest.TestCase):
    """Regression guard for the lifio-implementer discovery root cause.

    V1 `agent` key + V2 `model#variant` was dropped at load
    (`omitted unsupported legacy model reference` -> AgentNotFound).
    Config must stay pure V2: `agents` plural, `model#variant` inline,
    no legacy per-agent keys, variants within the confirmed set.
    """

    CONFIRMED_VARIANTS = {"low", "medium", "high", "xhigh"}

    def setUp(self):
        import json
        import re

        repo = Path(__file__).resolve().parent.parent
        self.cfg = json.loads((repo / "opencode.json").read_text())
        self.pattern = re.compile(r"^[^/#]+/[^#]+(?:#[^#]+)?$")

    def test_v2_agents_key(self):
        self.assertIn("agents", self.cfg)
        self.assertNotIn("agent", self.cfg)

    def test_no_legacy_per_agent_keys(self):
        legacy = {"reasoningEffort", "permission", "variant", "prompt", "disable"}
        for name, entry in self.cfg["agents"].items():
            self.assertEqual(
                set(entry) & legacy,
                set(),
                f"agent {name} uses legacy keys",
            )

    def test_model_shapes_and_variants(self):
        for name, entry in self.cfg["agents"].items():
            model = entry.get("model")
            if model is None:
                continue
            self.assertRegex(model, self.pattern, f"agent {name} model shape")
            if "#" in model:
                variant = model.split("#", 1)[1]
                self.assertIn(
                    variant,
                    self.CONFIRMED_VARIANTS,
                    f"agent {name} variant {variant} unconfirmed",
                )

    def test_lifio_implementer_present(self):
        entry = self.cfg["agents"].get("lifio-implementer")
        self.assertIsNotNone(entry)
        self.assertEqual(entry.get("mode"), "subagent")


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=2)
    sys.exit(0 if result.result.wasSuccessful() else 1)
