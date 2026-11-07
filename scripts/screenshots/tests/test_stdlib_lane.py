#!/usr/bin/env python3
"""Stdlib-only lane guard (CI tooling-tests has no Pillow).

The tooling-tests lane runs every file in this directory on Ubuntu
with stdlib only (`for t in scripts/screenshots/tests/test_*.py; do
python3 "$t"` — no pip install; Pillow lives in the macOS
panels-tests lane). Statically scans every .py file under
scripts/screenshots (source + tests) for REAL import statements
binding Pillow/panels modules and fails on any hit.

Scope is deliberately narrow: AST Import/ImportFrom nodes only, so
comments, docstrings, and string literals mentioning panels never
trip it; dynamic importlib-by-string games are out of scope (that
would be deliberate sabotage, not an accidental dependency).
"""

import ast
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent

# Module roots that may only be imported in the Pillow lane.
BANNED = frozenset({"pil", "pillow", "panels", "builder"})


def static_import_roots(path: Path) -> set[str]:
    """Root module names from real import statements in one file."""
    roots: set[str] = set()
    tree = ast.parse(path.read_text(encoding="utf-8"),
                     filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                roots.add(alias.name.split(".")[0].lower())
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                roots.add(node.module.split(".")[0].lower())
    return roots


class StdlibLaneTests(unittest.TestCase):
    def test_no_pillow_or_panels_imports(self):
        hits = []
        for path in sorted(HERE.rglob("*.py")):
            if "__pycache__" in path.parts:
                continue
            try:
                banned = static_import_roots(path) & BANNED
            except (OSError, SyntaxError) as exc:
                self.fail(f"cannot parse {path}: {exc}")
            for name in sorted(banned):
                hits.append(f"{path.relative_to(HERE)} imports {name}")
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
