#!/usr/bin/env python3
"""Per-locale artifact/status helpers (task 6.6 helper only, stdlib only).

Naming (`shots-<device>-<locale>` with hyphenated-locale-safe parsing),
explicit failed/unattempted status records, and worker summaries for the
packaging stage. No workflow rewiring, no uploads, no simulators here.
"""

from __future__ import annotations

import json
import os
import re
import shutil
from pathlib import Path

import workflow_inputs as inputs

STATUS_OK = "ok"
STATUS_FAILED = "failed"
STATUS_UNATTEMPTED = "unattempted"
STATUSES = (STATUS_OK, STATUS_FAILED, STATUS_UNATTEMPTED)

STATUS_SCHEMA_VERSION = 1
_STATUS_KEYS = frozenset({"schema_version", "device", "locale", "pass",
                          "status", "reason", "run_id"})

PASSES = ("r1", "r2")

ARTIFACT_PREFIX = "shots-"

# Run identifiers flow into runs/<run-id> paths downstream, so they use
# the same strict shape as capture run ids (mirrors
# request_schema.RUN_ID_RE; defined here to keep this helper stdlib-only
# with no new import).
_RUN_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class ArtifactError(ValueError):
    """Fail-closed artifact/status error."""


def artifact_name(device: str, locale: str) -> str:
    """Independent per-pair artifact name for upload-artifact v4."""
    if device not in inputs.SUPPORTED_DEVICES:
        raise ArtifactError(
            f"unknown device {device!r}; "
            f"catalog: {list(inputs.SUPPORTED_DEVICES)}")
    if locale not in inputs.SUPPORTED_LOCALES:
        raise ArtifactError(
            f"unknown language {locale!r}; "
            f"locales: {list(inputs.SUPPORTED_LOCALES)}")
    return f"{ARTIFACT_PREFIX}{device}-{locale}"


def parse_artifact_name(name: str) -> tuple[str, str]:
    """Split `shots-<device>-<locale>` by longest device-prefix match.

    Three locales contain a hyphen (es-419/zh-Hans/pt-BR), so splitting on
    the last hyphen misroutes cells (same rule as the workflow reshard).
    """
    if not isinstance(name, str) or not name.startswith(ARTIFACT_PREFIX):
        raise ArtifactError(
            f"artifact name must start with {ARTIFACT_PREFIX!r}, "
            f"got {name!r}")
    rest = name[len(ARTIFACT_PREFIX):]
    device = ""
    for cand in inputs.SUPPORTED_DEVICES:
        if rest == cand or rest.startswith(cand + "-"):
            if len(cand) > len(device):
                device = cand
    if not device:
        raise ArtifactError(
            f"cannot derive device from artifact {name!r}")
    locale = rest[len(device) + 1:] if rest != device else ""
    if not locale or locale not in inputs.SUPPORTED_LOCALES:
        raise ArtifactError(
            f"cannot derive language from artifact {name!r}")
    return device, locale


def expected_passes() -> tuple[str, str]:
    return PASSES


def status_record(*, device: str, locale: str, pass_name: str,
                  status: str, reason: str = "",
                  run_id: str | None = None) -> dict:
    """Explicit per-pass status. Non-ok without a reason is rejected: the
    worker summary must explain failed/unattempted, never stay silent."""
    if device not in inputs.SUPPORTED_DEVICES:
        raise ArtifactError(f"unknown device {device!r}")
    if locale not in inputs.SUPPORTED_LOCALES:
        raise ArtifactError(f"unknown language {locale!r}")
    if pass_name not in PASSES:
        raise ArtifactError(
            f"pass_name must be one of {list(PASSES)}, got {pass_name!r}")
    if status not in STATUSES:
        raise ArtifactError(
            f"status must be one of {list(STATUSES)}, got {status!r}")
    if status != STATUS_OK and not (isinstance(reason, str) and reason.strip()):
        raise ArtifactError(
            f"status {status!r} requires a non-empty reason")
    if run_id is not None and (
            not isinstance(run_id, str) or not _RUN_ID_RE.match(run_id)):
        raise ArtifactError(
            f"status run_id {run_id!r} must match [A-Za-z0-9_-]{{1,64}}")
    return {
        "schema_version": STATUS_SCHEMA_VERSION,
        "device": device, "locale": locale, "pass": pass_name,
        "status": status, "reason": reason.strip(),
        "run_id": run_id or f"{device}-{locale}-{pass_name}",
    }


def validate_status_record(record: dict) -> dict:
    """Strict shape/catalog gate for the write/load boundary.

    Requires the exact status_record key set and schema, string field
    types, a non-empty run_id, and byte-equality with a fresh
    status_record rebuild — unknown devices/locales/passes/statuses,
    missing reasons, bad schemas, extra keys, and denormalized fields
    are rejected, never silently normalized. Catalog-validated
    device/locale/pass values contain no separators, so a validated
    record cannot escape out_dir via status_path_for."""
    if not isinstance(record, dict):
        raise ArtifactError("status record must be a JSON object")
    if set(record) != _STATUS_KEYS:
        raise ArtifactError(
            f"status record keys must be exactly {sorted(_STATUS_KEYS)}; "
            "unknown shapes are rejected, never normalized")
    if (not isinstance(record["schema_version"], int)
            or isinstance(record["schema_version"], bool)
            or record["schema_version"] != STATUS_SCHEMA_VERSION):
        raise ArtifactError(
            f"status schema_version {record['schema_version']!r} != "
            f"supported {STATUS_SCHEMA_VERSION}")
    for key in ("device", "locale", "pass", "status", "reason"):
        if not isinstance(record[key], str):
            raise ArtifactError(f"status {key} must be a string")
    run_id = record["run_id"]
    if not isinstance(run_id, str) or not run_id:
        raise ArtifactError("status run_id must be a non-empty string")
    rebuilt = status_record(device=record["device"], locale=record["locale"],
                            pass_name=record["pass"], status=record["status"],
                            reason=record["reason"], run_id=run_id)
    if rebuilt != record:
        raise ArtifactError(
            "status record fails revalidation against the catalog "
            "(unknown device/locale/pass/status, missing reason, or "
            "denormalized fields); refusing to persist it")
    return rebuilt


def status_path_for(out_dir: Path, record: dict) -> Path:
    valid = validate_status_record(record)
    return (Path(out_dir)
            / f"{valid['device']}-{valid['locale']}-{valid['pass']}"
            ".status.json")


def write_status(out_dir: Path, record: dict) -> Path:
    path = status_path_for(out_dir, record)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(record, sort_keys=True, separators=(",", ":"),
                   ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def load_status(path: Path) -> dict:
    try:
        obj = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactError(f"cannot read status {path}: {exc}")
    if not isinstance(obj, dict):
        raise ArtifactError(f"status {path} must contain a JSON object")
    try:
        return validate_status_record(obj)
    except ArtifactError as exc:
        raise ArtifactError(f"status {path} rejected: {exc}")


def locale_artifact_dir(shots_root: Path, device: str, locale: str) -> Path:
    """On-disk layout preserved for packaging consumers."""
    if device not in inputs.SUPPORTED_DEVICES:
        raise ArtifactError(f"unknown device {device!r}")
    if locale not in inputs.SUPPORTED_LOCALES:
        raise ArtifactError(f"unknown language {locale!r}")
    return Path(shots_root) / device / locale


def stage_pair_upload(shots_root: Path, device: str, locale: str) -> Path:
    """Stage one uploadable pair directory: the locale cell plus the
    device worker summary copied in (when the worker wrote one).

    Keeps every per-locale CI upload self-contained at a SINGLE root so
    the packaging reshard never nests a locale inside a locale. The
    device-root summary stays authoritative; the copy is byte-identical
    and the operation is idempotent."""
    pair = locale_artifact_dir(shots_root, device, locale)
    pair.mkdir(parents=True, exist_ok=True)
    summary = Path(shots_root) / device / "worker-summary.json"
    if summary.is_file():
        (pair / "worker-summary.json").write_bytes(
            summary.read_bytes())
    return pair


def reshard_downloaded_artifacts(download_dir: Path,
                                 out_dir: Path) -> dict:
    """Flatten download-artifact nesting into shots/<device>/<locale>/.

    Each downloaded artifact holds one pair cell at its root (runs/,
    statuses, summary copy). Device keys come from longest catalog
    prefix match so hyphenated locales (es-419/zh-Hans/pt-BR) never
    misroute; unknown artifact names fail closed. Returns
    {"cells": n, "manifests": m}; zero run manifests fails closed.
    """
    download_dir = Path(download_dir)
    out_dir = Path(out_dir)
    cells = 0
    for child in sorted(download_dir.iterdir()):
        if not child.is_dir() or child.is_symlink():
            continue
        if not child.name.startswith(ARTIFACT_PREFIX):
            continue
        device, locale = parse_artifact_name(child.name)
        cell = locale_artifact_dir(out_dir, device, locale)
        cell.mkdir(parents=True, exist_ok=True)
        for member in sorted(child.iterdir()):
            target = cell / member.name
            if target.exists() or target.is_symlink():
                raise ArtifactError(
                    f"reshard collision at {target}")
            if member.is_dir() and not member.is_symlink():
                shutil.copytree(member, target, symlinks=True)
            elif member.is_file() or member.is_symlink():
                if member.is_symlink():
                    target.symlink_to(os.readlink(member))
                else:
                    shutil.copyfile(member, target)
            else:
                raise ArtifactError(
                    f"reshard refuses special file {member}")
        cells += 1
    manifests = list(out_dir.rglob("run-manifest.json"))
    if not manifests:
        raise ArtifactError("no run manifests after reshard")
    return {"cells": cells, "manifests": len(manifests)}


def backfill_unattempted(shots_root: Path, device: str,
                         locales: list[str], reason: str) -> list[dict]:
    """Write explicit unattempted statuses for pairs the worker never
    reached (pre-capture failure, cancel). Existing records are never
    touched: finished ok/failed evidence is preserved and only missing
    files are created. Empty/blank reasons are rejected — silence must
    never stand in for an explicit status."""
    if device not in inputs.SUPPORTED_DEVICES:
        raise ArtifactError(f"unknown device {device!r}")
    if not isinstance(locales, list) or not locales:
        raise ArtifactError("locales must be a non-empty list")
    for locale in locales:
        if locale not in inputs.SUPPORTED_LOCALES:
            raise ArtifactError(f"unknown language {locale!r}")
    if not isinstance(reason, str) or not reason.strip():
        raise ArtifactError("backfill reason must be a non-empty string")
    created: list[dict] = []
    for locale in locales:
        cell = locale_artifact_dir(shots_root, device, locale)
        cell.mkdir(parents=True, exist_ok=True)
        for pass_name in PASSES:
            path = cell / f"{device}-{locale}-{pass_name}.status.json"
            if path.exists() or path.is_symlink():
                continue
            rec = status_record(device=device, locale=locale,
                                pass_name=pass_name,
                                status=STATUS_UNATTEMPTED, reason=reason)
            write_status(cell, rec)
            created.append(rec)
    return created


def summarize_statuses(records: list[dict]) -> dict:
    counts = {STATUS_OK: 0, STATUS_FAILED: 0, STATUS_UNATTEMPTED: 0}
    failed: list[dict] = []
    unattempted: list[dict] = []
    for rec in records:
        status = rec.get("status")
        if status not in STATUSES:
            raise ArtifactError(f"unknown status {status!r}")
        counts[status] += 1
        if status == STATUS_FAILED:
            failed.append(rec)
        elif status == STATUS_UNATTEMPTED:
            unattempted.append(rec)
    return {"counts": counts, "failed": failed, "unattempted": unattempted}


def worker_summary(device: str, locales: list[str],
                   records: list[dict]) -> dict:
    """Per-pair completeness: both passes ok, else explicit failure or
    missing (never invented as complete)."""
    by_pair: dict[tuple[str, str, str], dict] = {}
    for rec in records:
        if rec.get("device") != device:
            continue
        by_pair[(rec.get("device"), rec.get("locale"), rec.get("pass"))] = rec
    pairs = []
    for locale in locales:
        passes = [by_pair.get((device, locale, p)) for p in PASSES]
        if all(p is not None and p.get("status") == STATUS_OK
               for p in passes):
            pairs.append({"device": device, "locale": locale,
                          "status": "complete", "complete": True})
        elif any(p is None for p in passes):
            pairs.append({"device": device, "locale": locale,
                          "status": "missing", "complete": False})
        else:
            pairs.append({"device": device, "locale": locale,
                          "status": "incomplete", "complete": False})
    return {"device": device, "locales": list(locales), "pairs": pairs}
