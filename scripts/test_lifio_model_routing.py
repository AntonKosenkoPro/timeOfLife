#!/usr/bin/env python3
"""Focused tests for Lifio-owned model-routing wrappers.

Proves: 5 model pins, $ARGUMENTS forwarding, lifio-implementer delegation
in apply/pr, skill references without duplicated workflows, generated
opsx-* files untouched (no pins), and opencode.json V2 agent shape.

Run: python3 scripts/test_lifio_model_routing.py
Pure file-content checks; touches no iOS build resources.
"""

import re
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COMMANDS = REPO / ".opencode" / "commands"

# wrapper -> (expected model, expected skill id)
WRAPPERS = {
    "lifio-explore": ("openai/gpt-6.1-sol#high", "openspec-explore"),
    "lifio-propose": ("openai/gpt-6.1-sol#high", "openspec-propose"),
    "lifio-apply": ("openai/gpt-6.1-sol#medium", "openspec-apply-change"),
    "lifio-archive": ("openai/gpt-6.1-sol#medium", "openspec-archive-change"),
    "lifio-pr": ("openai/gpt-6.1-sol#medium", "process-pr"),
}

# generated files that must stay upstream/unpinned
GENERATED = [
    "opsx-apply",
    "opsx-archive",
    "opsx-explore",
    "opsx-pr",
    "opsx-propose",
]


def read(name: str) -> str:
    return (COMMANDS / f"{name}.md").read_text()


def frontmatter(text: str):
    lines = text.split("\n")
    assert lines[0].strip() == "---", "missing frontmatter"
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i], "\n".join(lines[i + 1 :])
    raise AssertionError("unterminated frontmatter")


class WrapperRoutingTests(unittest.TestCase):
    def test_five_pins(self):
        self.assertEqual(len(WRAPPERS), 5)
        for name, (model, _skill) in WRAPPERS.items():
            fm, _body = frontmatter(read(name))
            models = [l for l in fm if l.startswith("model:")]
            self.assertEqual(len(models), 1, f"{name} must pin exactly one model")
            self.assertEqual(models[0], f"model: {model}", f"{name} model")

    def test_arguments_forwarding(self):
        for name in WRAPPERS:
            _fm, body = frontmatter(read(name))
            self.assertIn("$ARGUMENTS", body, f"{name} must forward $ARGUMENTS")

    def test_skill_referenced_not_duplicated(self):
        for name, (_model, skill) in WRAPPERS.items():
            _fm, body = frontmatter(read(name))
            self.assertIn(f"`{skill}`", body, f"{name} must load skill {skill}")

    def test_delegation_in_apply_and_pr(self):
        for name in ("lifio-apply", "lifio-pr"):
            _fm, body = frontmatter(read(name))
            self.assertIn("lifio-implementer", body, f"{name} must delegate")
            self.assertIn("Do not implement", body, f"{name} orchestrator guard")

    def test_generated_files_untouched(self):
        for name in GENERATED:
            text = read(name)
            fm, body = frontmatter(text)
            self.assertEqual(
                [l for l in fm if l.startswith("model:")],
                [],
                f"generated {name} must stay unpinned",
            )
            self.assertNotIn(
                "lifio-implementer", text, f"generated {name} must stay upstream"
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

        self.cfg = json.loads((REPO / "opencode.json").read_text())
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
