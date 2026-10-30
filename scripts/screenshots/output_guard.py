#!/usr/bin/env python3
"""External output-root guard + cross-process capture lock (stdlib only)."""

from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

LOCK_NAME_TEMPLATE = "lifio-capture-{udid}.lock"
LOCK_RUN_RE = re.compile(r"^run_id=([A-Za-z0-9_-]{1,64})$")
LOCK_PID_RE = re.compile(r"^pid=(\d+)$")


class GuardError(ValueError):
    pass


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def resolve_out_root(out: str) -> Path:
    """Resolve symlinks; reject repo-contained roots (fail-closed)."""
    if not out:
        raise GuardError("output root is required")
    p = Path(out).expanduser()
    try:
        resolved = p.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise GuardError(f"cannot resolve output root {out!r}: {exc}")
    root = repo_root().resolve()
    if resolved == root or root in resolved.parents:
        raise GuardError(
            f"output root {resolved} is inside the repository ({root}); "
            "screenshot binaries must stay outside git"
        )
    return resolved


def ensure_out_root(out: str) -> Path:
    """Validate an existing external root (no creation of run folders here)."""
    resolved = resolve_out_root(out)
    if not resolved.is_dir():
        raise GuardError(f"output root {resolved} does not exist or is not a directory")
    if not os.access(resolved, os.W_OK):
        raise GuardError(f"output root {resolved} is not writable")
    return resolved


def lock_path_for(udid: str) -> Path:
    """Device-global lock path (shared tmpdir, NOT the output root).

    Two output roots must never allow parallel capture on the same UDID,
    so the lock lives outside any single run directory.
    """
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in udid)
    return Path(tempfile.gettempdir()) / LOCK_NAME_TEMPLATE.format(
        udid=safe or "unknown"
    )


def _lock_owner(lock_path: Path) -> tuple[str, int] | None:
    """Parse exact owner identity; None when unparsable/foreign."""
    try:
        lines = lock_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    if len(lines) != 2:
        return None
    run_m = LOCK_RUN_RE.match(lines[0].strip())
    pid_m = LOCK_PID_RE.match(lines[1].strip())
    if not run_m or not pid_m:
        return None
    return run_m.group(1), int(pid_m.group(1))


def acquire_lock(udid: str, run_id: str) -> Path:
    """Exclusive cross-process lock per device; raises GuardError when held."""
    lp = lock_path_for(udid)
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    try:
        fd = os.open(str(lp), flags, 0o600)
    except FileExistsError:
        owner = _lock_owner(lp)
        holder = f"run_id={owner[0]} pid={owner[1]}" if owner else "unparsable"
        raise GuardError(
            f"capture lock held for device {udid!r} at {lp} (holder: {holder}); "
            "one capture simulator at a time — retry after release"
        )
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(f"run_id={run_id}\npid={os.getpid()}\n")
    return lp


def release_lock(lock_path: Path, run_id: str) -> None:
    """Remove only a lock exactly owned by this run; never touch others."""
    try:
        if not lock_path.exists():
            return
    except OSError:
        return
    owner = _lock_owner(lock_path)
    if owner is None:
        raise GuardError(
            f"refusing to release unparsable lock {lock_path} for run {run_id!r}"
        )
    if owner[0] != run_id:
        raise GuardError(
            f"refusing to release lock {lock_path} owned by run {owner[0]!r} "
            f"(caller {run_id!r})"
        )
    lock_path.unlink()


def run_dir_for(out_root: Path, run_id: str) -> Path:
    return out_root / "runs" / run_id
