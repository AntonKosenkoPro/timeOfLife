#!/usr/bin/env python3
"""Shared Screenshot build artifact helpers (tasks 6.2-6.4, stdlib only).

Pure foundations for the one-build stage: explicit toolchain pin (Xcode
marketing version + build identifier) + arm64-only slice inspection,
locale/pass-independent build keys, dependency-cache usability (the
normal build ALWAYS runs after any restore; a cache hit never
substitutes the final artifact — build-intermediate caching stays a
pending measured refinement per design §2, not shipped here),
permission-preserving tar with fail-closed extraction, full resource
hashes, the realistic iOS .app layout with exact appex identities, and
provenance/toolchain/config mismatch detection incl. schema version and
capture bundle identities.

Layout ground truth (read-only inspection of a local
Screenshot-iphonesimulator TimeOfLife.app, no builds/simulators): root
Info.plist + root executable, PlugIns/LifioLiveActivities.appex with
root Info.plist + executable, zero symlinks and zero hardlinked files
in the shipped product. verify_app_structure enforces exactly that iOS
shape — the macOS Contents/MacOS layout is rejected.

No device I/O, no builds here: unit proof only. Actual arm64
build/install-per-device acceptance stays open (tasks 6.5/8.x) and is
NOT claimed by these helpers. No new external dependency (stdlib:
hashlib/json/re/tarfile/plistlib), so no fresh ctx7 fetch beyond
evidence/research.md (upload-artifact permission-loss + dependency
caching + Xcode ARCHS/ONLY_ACTIVE_ARCH notes).
"""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import stat
import tarfile
from pathlib import Path, PurePosixPath

SCHEMA_VERSION = 1
SCREENSHOT_CONFIGURATION = "Screenshot"
EXPECTED_ARCH = "arm64"

# Exact capture identities (project.yml Screenshot overrides + observed
# Screenshot-iphonesimulator product; cross-checked against
# request_schema.SCREENSHOT_BID in tests).
SCREENSHOT_BUNDLE_ID = "com.antonkosenko.timeoflifeapp.screenshots"
SCREENSHOT_EXTENSION_ID = (
    "com.antonkosenko.timeoflifeapp.screenshots.liveactivities")
SCREENSHOT_APPEX_NAME = "LifioLiveActivities.appex"
SCREENSHOT_APPEX_EXECUTABLE = "LifioLiveActivities"

HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
_XCODE_RE = re.compile(r"Xcode\s+(\d+\.\d+(?:\.\d+)?)")
_XCODE_BUILD_RE = re.compile(r"Build version\s+(\S+)")
_ARCH_TOKEN_RE = re.compile(r"^[A-Za-z0-9_]+$")


class ArtifactError(ValueError):
    """Fail-closed build artifact error."""


# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------

def parse_xcode_version(output: str) -> str:
    """Extract the Xcode marketing version from `xcodebuild -version`."""
    if not isinstance(output, str):
        raise ArtifactError("xcodebuild output must be a string")
    m = _XCODE_RE.search(output)
    if not m:
        raise ArtifactError(
            f"cannot parse Xcode version from {output!r:.120}")
    return m.group(1)


def parse_xcode_build(output: str) -> str:
    """Extract the Xcode build identifier (`Build version 17C00` line).

    Provenance records both the marketing version and this build id; the
    workflow integration populates them from the same `xcodebuild
    -version` output (pending 6.2 wiring, not claimed here)."""
    if not isinstance(output, str):
        raise ArtifactError("xcodebuild output must be a string")
    m = _XCODE_BUILD_RE.search(output)
    if not m:
        raise ArtifactError(
            f"cannot parse Xcode build from {output!r:.120}")
    return m.group(1)


def validate_xcode_pin(actual: str, expected: str) -> list[str]:
    """Exact pin match (e.g. baseline 27.1); any drift is an error."""
    if not isinstance(actual, str) or not actual:
        return ["xcode_version is required"]
    if not isinstance(expected, str) or not expected:
        return ["expected Xcode pin is required"]
    if actual != expected:
        return [f"Xcode {actual!r} != pinned {expected!r}"]
    return []


# ---------------------------------------------------------------------------
# Build identity (locale/pass-independent by construction)
# ---------------------------------------------------------------------------

def build_key(*, commit: str, xcode_version: str, xcode_build: str,
              sdk_version: str, sdk_build: str, arch: str,
              configuration: str) -> str:
    """Deterministic build key. No device/locale/pass input exists, so no
    per-locale/pass rebuild can be keyed (see BuildKeyTests signature
    assertion). Any toolchain/arch/config/commit change re-keys. Exact
    Xcode/SDK *build* IDs are key inputs — a rebuilt toolchain never
    shares a key with its predecessor, so stale checkouts cannot hide
    behind a marketing-version match."""
    for label, val in (("commit", commit), ("xcode_version", xcode_version),
                       ("xcode_build", xcode_build),
                       ("sdk_version", sdk_version),
                       ("sdk_build", sdk_build), ("arch", arch),
                       ("configuration", configuration)):
        if not isinstance(val, str) or not val:
            raise ArtifactError(f"build key {label} must be a non-empty string")
    canonical = json.dumps({
        "commit": commit, "xcode_version": xcode_version,
        "xcode_build": xcode_build, "sdk_version": sdk_version,
        "sdk_build": sdk_build, "arch": arch,
        "configuration": configuration,
    }, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


# ---------------------------------------------------------------------------
# Dependency caching (usability only — never a build substitute)
# ---------------------------------------------------------------------------

def dependency_cache_key(lock_hashes: dict[str, str], xcode_version: str,
                         xcode_build: str, sdk_version: str,
                         sdk_build: str, arch: str,
                         configuration: str) -> str:
    """Cache key from dependency lockfiles + the EXACT toolchain/SDK
    builds + arch/config. Marketing versions alone are insufficient: a
    rebuilt Xcode/SDK under one version string must re-key."""
    if not isinstance(lock_hashes, dict) or not lock_hashes:
        raise ArtifactError("lock hashes must be a non-empty object")
    for path, digest in lock_hashes.items():
        if not isinstance(path, str) or not path:
            raise ArtifactError("lock paths must be non-empty strings")
        if not isinstance(digest, str) or not HEX64_RE.match(digest):
            raise ArtifactError(
                f"lock hash for {path!r} must be a hex sha256")
    for label, val in (("xcode_version", xcode_version),
                       ("xcode_build", xcode_build),
                       ("sdk_version", sdk_version),
                       ("sdk_build", sdk_build), ("arch", arch),
                       ("configuration", configuration)):
        if not isinstance(val, str) or not val:
            raise ArtifactError(f"cache key {label} must be a non-empty string")
    canonical = json.dumps({
        "locks": lock_hashes, "xcode_version": xcode_version,
        "xcode_build": xcode_build, "sdk_version": sdk_version,
        "sdk_build": sdk_build, "arch": arch,
        "configuration": configuration,
    }, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def check_cache_hit_usable(cached_manifest: dict, *, expected_commit: str,
                           expected_xcode: str, expected_xcode_build: str,
                           expected_sdk_version: str,
                           expected_sdk_build: str,
                           expected_runtime_version: str,
                           expected_runtime_build: str,
                           expected_arch: str, expected_configuration: str,
                           expected_bundle_id: str,
                           expected_extension_id: str) -> list[str]:
    """Reject an incompatible dependency-cache hit; empty means restorable.

    Usability gates dependency restore ONLY. The normal Screenshot build
    is always invoked after any restore and the final installable
    artifact is always the product of the current build, verified via
    verify_manifest — a cache hit can never substitute a loose app."""
    if not isinstance(cached_manifest, dict):
        return ["cached manifest must be a JSON object"]
    return _identity_errors(cached_manifest, {
        "commit": expected_commit, "xcode_version": expected_xcode,
        "xcode_build": expected_xcode_build,
        "sdk_version": expected_sdk_version,
        "sdk_build": expected_sdk_build,
        "runtime_version": expected_runtime_version,
        "runtime_build": expected_runtime_build,
        "arch": expected_arch,
        "configuration": expected_configuration,
        "bundle_id": expected_bundle_id,
        "extension_id": expected_extension_id,
    }, "cache")


def cache_usable(cache_hit: bool, usability_errors: list) -> bool:
    """True only on a cache hit with zero usability errors. A miss or an
    incompatible hit means dependencies reinstall from lockfiles — and in
    every case the normal build still runs afterwards."""
    return bool(cache_hit) and not usability_errors


# ---------------------------------------------------------------------------
# Build manifest + provenance
# ---------------------------------------------------------------------------

def _require_hex(name: str, val: object) -> None:
    if not isinstance(val, str) or not HEX64_RE.match(val):
        raise ArtifactError(f"{name} must be a hex sha256")


def build_manifest(*, commit: str, dirty: bool, configuration: str,
                   xcode_version: str, xcode_build: str,
                   sdk_version: str, sdk_build: str,
                   runtime_version: str, runtime_build: str,
                   arch: str,
                   app_sha256: str, extension_sha256: str,
                   archive_sha256: str, bundle_id: str,
                   extension_id: str,
                   resources: dict | None = None) -> dict:
    """Authoritative build record. Strict at build time: Screenshot config
    + arm64 only (a generic simulator destination does not make
    ONLY_ACTIVE_ARCH sufficient; slices are inspected separately).

    Toolchain identity is exact, never marketing-only: xcode_build (e.g.
    "27A9275" from `xcodebuild -version`), sdk_version/sdk_build (e.g.
    "27.1"/"24A94232" from `xcrun --sdk iphonesimulator --show-sdk-*`),
    plus the REQUESTED simulator runtime version/build (e.g. "iOS 27.0"/
    "24A434" from `simctl list runtimes -j`). SDK and runtime are
    recorded separately — a runtime build is never presented as an SDK
    build. `resources` optionally carries the full {files, symlinks} map
    for post-extraction verification."""
    if not isinstance(commit, str) or not commit:
        raise ArtifactError("commit must be a non-empty string")
    if not isinstance(dirty, bool):
        raise ArtifactError("dirty must be a bool")
    if configuration != SCREENSHOT_CONFIGURATION:
        raise ArtifactError(
            f"configuration must be {SCREENSHOT_CONFIGURATION!r}, "
            f"got {configuration!r}")
    if arch != EXPECTED_ARCH:
        raise ArtifactError(
            f"arch must be {EXPECTED_ARCH!r} for the capture fleet, "
            f"got {arch!r}")
    for label, val in (("xcode_version", xcode_version),
                       ("xcode_build", xcode_build),
                       ("sdk_version", sdk_version),
                       ("sdk_build", sdk_build),
                       ("runtime_version", runtime_version),
                       ("runtime_build", runtime_build),
                       ("bundle_id", bundle_id),
                       ("extension_id", extension_id)):
        if not isinstance(val, str) or not val:
            raise ArtifactError(f"{label} must be a non-empty string")
    _require_hex("app_sha256", app_sha256)
    _require_hex("extension_sha256", extension_sha256)
    _require_hex("archive_sha256", archive_sha256)
    manifest: dict = {
        "schema_version": SCHEMA_VERSION,
        "commit": commit, "dirty": dirty,
        "configuration": configuration,
        "xcode_version": xcode_version, "xcode_build": xcode_build,
        "sdk_version": sdk_version, "sdk_build": sdk_build,
        "runtime_version": runtime_version, "runtime_build": runtime_build,
        "arch": arch, "app_sha256": app_sha256,
        "extension_sha256": extension_sha256,
        "archive_sha256": archive_sha256,
        "bundle_id": bundle_id, "extension_id": extension_id,
    }
    if resources is not None:
        if not isinstance(resources, dict) \
                or not isinstance(resources.get("files"), dict) \
                or not isinstance(resources.get("symlinks"), dict):
            raise ArtifactError(
                "resources must be {files: {...}, symlinks: {...}}")
        manifest["resources"] = {"files": dict(resources["files"]),
                                 "symlinks": dict(resources["symlinks"])}
    return manifest


def manifest_bytes(manifest: dict) -> bytes:
    return (json.dumps(manifest, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False).encode("utf-8") + b"\n")


def write_manifest(path: Path, manifest: dict) -> Path:
    Path(path).write_bytes(manifest_bytes(manifest))
    return Path(path)


def load_manifest(path: Path) -> dict:
    try:
        obj = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactError(f"cannot read manifest {path}: {exc}")
    if not isinstance(obj, dict):
        raise ArtifactError(f"manifest {path} must contain a JSON object")
    return obj


def _identity_errors(manifest: dict, expected: dict[str, object],
                     label: str) -> list[str]:
    """Supported-schema gate + exact identity match (commit, toolchain,
    SDK, arch, configuration, capture bundle identities)."""
    errs: list[str] = []
    if manifest.get("schema_version") != SCHEMA_VERSION:
        errs.append(
            f"{label} schema_version {manifest.get('schema_version')!r} "
            f"!= supported {SCHEMA_VERSION}")
    for key, want in expected.items():
        if want is None:
            continue
        if manifest.get(key) != want:
            errs.append(
                f"{label} {key} {manifest.get(key)!r} != expected "
                f"{want!r}")
    return errs


def _shape_errors(manifest: dict, label: str) -> list[str]:
    errs: list[str] = []
    for key in ("app_sha256", "extension_sha256", "archive_sha256"):
        val = manifest.get(key)
        if not isinstance(val, str) or not HEX64_RE.match(val):
            errs.append(f"{label} {key} must be a hex sha256")
    if not isinstance(manifest.get("dirty"), bool):
        errs.append(f"{label} dirty must be a bool")
    if "resources" in manifest:
        res = manifest["resources"]
        if not isinstance(res, dict) \
                or not isinstance(res.get("files"), dict) \
                or not isinstance(res.get("symlinks"), dict):
            errs.append(f"{label} resources must be "
                        "{files: {...}, symlinks: {...}}")
    return errs


def verify_manifest(manifest: dict, *, expected_commit: str,
                    expected_xcode: str, expected_xcode_build: str,
                    expected_sdk_version: str, expected_sdk_build: str,
                    expected_runtime_version: str,
                    expected_runtime_build: str,
                    expected_arch: str, expected_configuration: str,
                    expected_bundle_id: str,
                    expected_extension_id: str) -> list[str]:
    """Worker-side provenance gate: any identity mismatch fails before
    install. dirty=True is recorded, never an install refusal by itself.
    Every toolchain/runtime/build field is REQUIRED here — callers pin
    the exact IDs they computed locally, never None."""
    if not isinstance(manifest, dict):
        return ["manifest must be a JSON object"]
    errs = _identity_errors(manifest, {
        "commit": expected_commit, "xcode_version": expected_xcode,
        "xcode_build": expected_xcode_build,
        "sdk_version": expected_sdk_version,
        "sdk_build": expected_sdk_build,
        "runtime_version": expected_runtime_version,
        "runtime_build": expected_runtime_build,
        "arch": expected_arch,
        "configuration": expected_configuration,
        "bundle_id": expected_bundle_id,
        "extension_id": expected_extension_id,
    }, "manifest")
    errs.extend(_shape_errors(manifest, "manifest"))
    return errs


# ---------------------------------------------------------------------------
# Slice inspection
# ---------------------------------------------------------------------------

def parse_lipo_archs(output: str) -> frozenset[str]:
    """Parse `lipo -archs` output into an arch set; fail-closed."""
    if not isinstance(output, str) or not output.split():
        raise ArtifactError("lipo output is empty")
    tokens = output.split()
    for tok in tokens:
        if not _ARCH_TOKEN_RE.match(tok):
            raise ArtifactError(f"unexpected lipo token {tok!r}")
    return frozenset(tokens)


def validate_slices(app_archs: frozenset[str],
                    ext_archs: frozenset[str],
                    expected: frozenset[str] = frozenset({EXPECTED_ARCH})
                    ) -> list[str]:
    """Both app and extension must be exactly arm64-only (no universal)."""
    errs: list[str] = []
    for label, archs in (("app", app_archs), ("extension", ext_archs)):
        if not isinstance(archs, frozenset) or not archs:
            errs.append(f"{label} slices missing")
        elif set(archs) != set(expected):
            errs.append(
                f"{label} slices {sorted(archs)} != expected "
                f"{sorted(expected)}")
    return errs


# ---------------------------------------------------------------------------
# File hashes + app structure
# ---------------------------------------------------------------------------

def hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 64), b""):
            h.update(chunk)
    return h.hexdigest()


def resource_hashes(app_dir: Path) -> dict[str, dict[str, str]]:
    """Full hashes: regular files and ALL symlink targets (lstat-based, so
    links to valid directories and broken links are recorded, never
    followed)."""
    app_dir = Path(app_dir)
    files: dict[str, str] = {}
    symlinks: dict[str, str] = {}
    for root, dirs, names in os.walk(app_dir, followlinks=False):
        dirs.sort()
        for name in sorted(dirs):
            p = Path(root) / name
            if p.is_symlink():
                rel = p.relative_to(app_dir).as_posix()
                symlinks.setdefault(rel, os.readlink(p))
        for name in sorted(names):
            p = Path(root) / name
            rel = p.relative_to(app_dir).as_posix()
            if p.is_symlink():
                symlinks.setdefault(rel, os.readlink(p))
            elif p.is_file():
                files[rel] = hash_file(p)
    return {"files": files, "symlinks": symlinks}


def verify_hashes(app_dir: Path, expected_files: dict[str, str],
                  expected_symlinks: dict[str, str] | None = None
                  ) -> list[str]:
    """Missing/tampered/extra resources all fail (complete bundle gate)."""
    actual = resource_hashes(Path(app_dir))
    errs: list[str] = []
    for rel, want in expected_files.items():
        got = actual["files"].get(rel)
        if got is None:
            errs.append(f"missing resource {rel!r}")
        elif got != want:
            errs.append(f"resource {rel!r} hash mismatch")
    for rel in actual["files"]:
        if rel not in expected_files:
            errs.append(f"unexpected extra resource {rel!r}")
    want_links = expected_symlinks or {}
    for rel, want in want_links.items():
        got = actual["symlinks"].get(rel)
        if got is None:
            errs.append(f"missing symlink {rel!r}")
        elif got != want:
            errs.append(f"symlink {rel!r} target {got!r} != {want!r}")
    for rel in actual["symlinks"]:
        if rel not in want_links:
            errs.append(f"unexpected extra symlink {rel!r}")
    return errs


def _load_plist(path: Path) -> tuple[dict | None, str]:
    try:
        with open(path, "rb") as fh:
            obj = plistlib.load(fh)
    except (OSError, ValueError) as exc:
        return None, f"{path.name} unreadable: {exc}"
    if not isinstance(obj, dict):
        return None, f"{path.name} must contain a plist dict"
    return obj, ""


def _check_executable(path: Path, label: str) -> str:
    if not path.is_file() or path.is_symlink():
        return f"{label} missing"
    if not (os.stat(path).st_mode & stat.S_IXUSR):
        return f"{label} lost its executable bit"
    return ""


def verify_app_structure(
        app_dir: Path, *,
        expected_bundle_id: str = SCREENSHOT_BUNDLE_ID,
        expected_extension_id: str = SCREENSHOT_EXTENSION_ID,
        expected_appex_name: str = SCREENSHOT_APPEX_NAME,
        expected_appex_executable: str = SCREENSHOT_APPEX_EXECUTABLE,
) -> list[str]:
    """iOS simulator product check: root Info.plist (exact capture bundle
    id + executable with exec bit) and the exact appex at
    PlugIns/<name> with root Info.plist carrying the exact extension
    executable + bundle id and that exact binary with exec bit.

    No glob-anyfile: a renamed appex, a wrong executable name, or a
    wrong bundle id fails. Other PlugIns members (if any) are ignored
    here — verify_hashes gates bundle completeness against the manifest.

    Structure alone does not attest symlink-freedom or bundle
    completeness: always pair with verify_hashes against the
    manifest-expected file/symlink maps before install.
    No device needed."""
    errs: list[str] = []
    app_dir = Path(app_dir)
    if app_dir.suffix != ".app" or not app_dir.is_dir():
        return [f"{app_dir} is not an .app directory"]
    info, err = _load_plist(app_dir / "Info.plist")
    if err:
        return [err]
    assert info is not None
    if info.get("CFBundleIdentifier") != expected_bundle_id:
        errs.append(
            f"CFBundleIdentifier {info.get('CFBundleIdentifier')!r} != "
            f"capture {expected_bundle_id!r}")
    exe = info.get("CFBundleExecutable")
    if not exe or not isinstance(exe, str):
        errs.append("Info.plist has no CFBundleExecutable")
    else:
        err = _check_executable(app_dir / exe, f"executable {exe!r}")
        if err:
            errs.append(err)
    apex = app_dir / "PlugIns" / expected_appex_name
    if not apex.is_dir() or apex.is_symlink():
        return errs + [f"extension {expected_appex_name!r} missing"]
    ext_info, err = _load_plist(apex / "Info.plist")
    if err:
        return errs + [f"extension {err}"]
    assert ext_info is not None
    if ext_info.get("CFBundleExecutable") != expected_appex_executable:
        errs.append(
            f"extension CFBundleExecutable "
            f"{ext_info.get('CFBundleExecutable')!r} != "
            f"{expected_appex_executable!r}")
    if ext_info.get("CFBundleIdentifier") != expected_extension_id:
        errs.append(
            f"extension CFBundleIdentifier "
            f"{ext_info.get('CFBundleIdentifier')!r} != "
            f"{expected_extension_id!r}")
    err = _check_executable(
        apex / expected_appex_executable,
        f"extension executable {expected_appex_executable!r}")
    if err:
        errs.append(err)
    return errs


def check_devices_installable(devices: list[str],
                              known_catalog: list[str],
                              manifest: dict) -> list[str]:
    """Every selected device must be known and the manifest arm64/Shot."""
    if not isinstance(manifest, dict):
        return ["manifest must be a JSON object"]
    errs: list[str] = []
    for d in devices:
        if d not in known_catalog:
            errs.append(f"unknown device {d!r}")
    if manifest.get("arch") != EXPECTED_ARCH:
        errs.append(
            f"manifest arch {manifest.get('arch')!r} is not installable "
            f"on the {EXPECTED_ARCH} simulator fleet")
    if manifest.get("configuration") != SCREENSHOT_CONFIGURATION:
        errs.append(
            f"manifest configuration {manifest.get('configuration')!r} != "
            f"{SCREENSHOT_CONFIGURATION!r}")
    return errs


# ---------------------------------------------------------------------------
# Permission-preserving tar + safe extraction
# ---------------------------------------------------------------------------

def pack_app(src_app_dir: Path, out_tar: Path) -> dict:
    """Tar a complete .app (extension+resources) preserving modes/symlinks.

    PAX_FORMAT keeps executable bits and symlink targets. Members use
    archive-relative names (never absolute). The real fleet product ships
    no hardlinks, so none are produced here; safe_extract rejects them.
    The returned archive digest identifies this build's tarball only
    (gzip embeds mtime, so tar bytes are not byte-reproducible across
    builds); workers verify provenance plus extracted hashes, never
    re-derive bytes."""
    src = Path(src_app_dir)
    if src.suffix != ".app" or not src.is_dir():
        raise ArtifactError(f"{src} is not an .app directory")
    out = Path(out_tar)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out, "w:gz", format=tarfile.PAX_FORMAT) as tf:
        tf.add(str(src), arcname=src.name, recursive=True)
    return {"archive_sha256": hash_file(out),
            "members": list_tar_members(out)}


def list_tar_members(tar_path: Path) -> list[str]:
    with tarfile.open(tar_path, "r:*") as tf:
        return [m.name for m in tf.getmembers()]


def _within_dest(dest: Path, rel: PurePosixPath) -> Path:
    """Resolve rel under dest; raise when absolute/traversal/escaping."""
    if rel.is_absolute() or rel.parts[:1] == ("/",):
        raise ArtifactError(f"tar member {str(rel)!r} is absolute")
    if ".." in rel.parts:
        raise ArtifactError(f"tar member {str(rel)!r} traverses upward")
    candidate = (dest / Path(*rel.parts)).resolve(strict=False)
    dest_resolved = dest.resolve(strict=False)
    if candidate != dest_resolved and dest_resolved not in candidate.parents:
        raise ArtifactError(f"tar member {str(rel)!r} escapes {dest}")
    return candidate


def _ensure_parent_dirs(dest: Path, target: Path) -> None:
    """Create ancestors without traversing planter symlinks or files."""
    try:
        parts = target.parent.relative_to(dest).parts
    except ValueError:
        raise ArtifactError(f"tar path escapes {dest}")
    cur = dest
    for part in parts:
        cur = cur / part
        if os.path.lexists(cur):
            if cur.is_symlink():
                raise ArtifactError(
                    f"tar path through planted symlink at {cur}; refusing")
            if not cur.is_dir():
                raise ArtifactError(
                    f"tar path blocked by non-directory at {cur}")
        else:
            cur.mkdir()


def safe_extract(tar_path: Path, dest_dir: Path) -> list[str]:
    """Fail-closed extraction, member by member (never bulk extract).

    Rejects absolute names, `..` traversal, absolute/escaping symlink
    targets, hardlink members (archive-root-relative targets the fleet
    never ships — the observed product has zero), device/fifo nodes,
    duplicate member names, and any write colliding with a preexisting
    file/symlink (dest inputs are never mutated through a link).
    Regular files are copied via fileobj with source modes applied
    (executable bits preserved, masked to 0o777). On error the
    destination may be partial: discard it, never install from it."""
    dest = Path(dest_dir).resolve(strict=False)
    dest.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    extracted: list[str] = []
    with tarfile.open(tar_path, "r:*") as tf:
        for member in tf.getmembers():
            if member.name in seen:
                raise ArtifactError(
                    f"tar member {member.name!r} appears twice; refusing")
            seen.add(member.name)
            rel = PurePosixPath(member.name)
            # Containment gate on the resolved path, but every decision
            # below uses the LEXICAL target: resolving first would follow
            # a planted in-tree symlink and mask alias traversal.
            _within_dest(dest, rel)
            target = dest.joinpath(*rel.parts)
            if member.ischr() or member.isblk() or member.isfifo():
                raise ArtifactError(
                    f"tar member {member.name!r} is a device/fifo node")
            if member.islnk():
                raise ArtifactError(
                    f"tar member {member.name!r} is a hardlink "
                    f"(target {member.linkname!r}); hardlinks are not "
                    "shipped — refusing")
            if member.issym():
                link_target = member.linkname
                if not link_target:
                    raise ArtifactError(
                        f"tar link {member.name!r} has an empty target")
                if PurePosixPath(link_target).is_absolute():
                    raise ArtifactError(
                        f"tar link {member.name!r} has absolute target "
                        f"{link_target!r}")
                resolved = (target.parent / Path(*PurePosixPath(
                    link_target).parts)).resolve(strict=False)
                dest_resolved = dest.resolve(strict=False)
                if (resolved != dest_resolved
                        and dest_resolved not in resolved.parents):
                    raise ArtifactError(
                        f"tar link {member.name!r} escapes {dest}")
                _ensure_parent_dirs(dest, target)
                if os.path.lexists(target):
                    raise ArtifactError(
                        f"tar link {member.name!r} collides with a "
                        "preexisting file; refusing to replace it")
                target.symlink_to(link_target)
                extracted.append(member.name)
            elif member.isdir():
                _ensure_parent_dirs(dest, target)
                if os.path.lexists(target):
                    if target.is_symlink() or not target.is_dir():
                        raise ArtifactError(
                            f"tar dir {member.name!r} collides with a "
                            "preexisting non-directory")
                else:
                    target.mkdir(parents=True, exist_ok=True)
                try:
                    os.chmod(target, member.mode & 0o777)
                except OSError as exc:
                    raise ArtifactError(
                        f"cannot set mode on {member.name!r}: {exc}")
                extracted.append(member.name)
            elif member.isfile():
                _ensure_parent_dirs(dest, target)
                if os.path.lexists(target):
                    raise ArtifactError(
                        f"tar member {member.name!r} collides with a "
                        "preexisting file; refusing to overwrite it")
                src = tf.extractfile(member)
                if src is None:
                    raise ArtifactError(
                        f"tar member {member.name!r} is unreadable")
                with open(target, "wb") as fh:
                    for chunk in iter(lambda: src.read(1024 * 64), b""):
                        fh.write(chunk)
                try:
                    os.chmod(target, member.mode & 0o777)
                except OSError as exc:
                    raise ArtifactError(
                        f"cannot set mode on {member.name!r}: {exc}")
                extracted.append(member.name)
            else:
                raise ArtifactError(
                    f"tar member {member.name!r} has unsupported type "
                    f"{member.type!r}")
    return extracted


def verify_extracted_modes(tar_path: Path, dest_root: Path) -> list[str]:
    """Prove extraction preserved permission modes (executability).

    Re-reads every archived regular file and directory and compares
    its on-disk mode against the tar member mode (masked to 0o777).
    Symlinks carry no portable mode and device/fifo/hardlink members
    are never extracted, so they are skipped here — safe_extract
    already rejects those shapes. Extra on-disk files are reported:
    the destination must contain exactly the archive, nothing else.
    """
    import tarfile

    dest_root = Path(dest_root)
    errs: list[str] = []
    seen: set[str] = set()
    with tarfile.open(tar_path, "r:*") as tf:
        for member in tf.getmembers():
            rel = PurePosixPath(member.name)
            if member.islnk() or member.ischr() or member.isblk() \
                    or member.isfifo() or member.issym():
                continue
            if not member.isfile() and not member.isdir():
                continue
            target = dest_root.joinpath(*rel.parts) if rel.parts \
                else dest_root
            seen.add(str(target))
            if not os.path.lexists(target) or target.is_symlink():
                errs.append(f"extracted member missing: {member.name!r}")
                continue
            want = member.mode & 0o777
            try:
                got = stat.S_IMODE(os.stat(target).st_mode)
            except OSError as exc:
                errs.append(f"cannot stat {member.name!r}: {exc}")
                continue
            if got != want:
                errs.append(
                    f"mode mismatch {member.name!r}: on-disk "
                    f"{got:o} != archived {want:o}")
    try:
        disk_files = {str(p) for p in dest_root.rglob("*")
                      if not p.is_symlink()}
    except OSError as exc:
        return errs + [f"cannot list {dest_root}: {exc}"]
    for extra in sorted(disk_files - seen):
        errs.append(f"unexpected extra file {extra!r}")
    return errs
