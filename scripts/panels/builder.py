#!/usr/bin/env python3
"""Store marketing panel builder (tasks 9.x/10.x): approved templates as code.

Promotion of the retained `panels/` builders into git (text only — no
binaries). Three compositions are encoded here:

- 6.9-inch iPhone (1320x2868), template v13: four singles (Track, Insights,
  History, Add-entry) with headline TOP + one LA-combined panel using the
  v11 owner-Figma geometry verbatim. Approved 2026-11-02 (composition only).
- 6.3-inch iPhone (1206x2622), template v13 scaled: the SAME v13
  composition (same 5 panels, same LA stacking) with every layout constant
  derived per-axis from the 6.9 values (x * 1206/1320, y * 2622/2868;
  derivation recorded in the recipe). Review sets only: no separate 6.3
  owner approval exists, so `--check-template` refuses 6.3 and the 9.3
  hold still applies. Non-Apple 6.3 bezels stay on the legacy structural
  verification (alpha slot detection, canvas-aspect agreement, opaque
  frame) — thresholds unchanged.
- 13-inch iPad (2064x2752), template ipad-v1: four singles, headline TOP,
  silver-bezel device, NO LA panel (iPad has no Island presentations and
  the owner scoped LA out of the iPad set). Approved 2026-11-02
  (composition only).

Owner lineup: iPhone 18 Pro Max Silver (iphone69 frame), iPhone 17
White, iPad Pro 13-inch (M5) Silver — official Apple PNG device art
delivered by the OWNER-DECIDED private versioned release
(`AntonKosenkoPro/lifio-design-assets`, `apple-bezels-v2`: 4 release PNGs
— 18PM current plus 17PM retained for history — + manifest, exact hash
verification before use; no Figma/Sketch/API export or DMG extraction, no
PNG in any git history, no public standalone redistribution; v1 stays
pinned for historical bundles already staged). Headline/story/layout
intent is preserved; renders on the new art are a NEW review template
version (no historical approval transfer, no auto-approved frozen hash
update — `--check-template` refuses the new-art profiles loudly instead
of blessing new goldens).

Rendering core is a behavior-preserving port of the retained
`build_final_v13.py` (6.9) and `ipad/build_ipad_panels_v1.py` (iPad)
lineages: same constants, same geometry, same fonts, same resampling,
same PNG save defaults. With `--locale en --size 6.9`, the legacy Figma
profile, and the retained v13 sources, outputs MUST be byte-identical to
the five approved v13 PNGs (see EXPECTED_EN69; enforced by
`--check-template`, which stays pinned to the legacy profile only).

Parametrization (locale/size/captions) changes ONLY the caption strings
and the CJK font selection — never geometry, point sizes, or layout.
Localized captions that do not fit the fixed template (taller headline
block, forced shot-top overlap, band overflow) fail loudly with measured
numbers for the 9.2 on-template review — never silently shrunk, wrapped
away, or reflowed. New app-visible strings are marketing overlay copy,
not app chrome: panel-only strings stay out of app L10n bundles.

Source honesty: every source PNG is hash-verified against its
run-manifest before use; art whose geometry differs from the canvas is
rejected (no cross-size stretching); incomplete runs are rejected.
Outputs are REVIEW SETS ONLY — not Store deliverables: matrix renders
stay HELD per 9.3 until chrome-fixed sources are verified frame-by-frame
and the retaken-set re-approval (5.4) lands. The recipe records run-id,
deck, treatment, source hashes, caption version, and renderer so the
approval gates (5.4/9.1/9.4) can bind them.

Dependencies: stdlib + Pillow (13.0.0 pinned by the approved recipes).
No device, no network, no simulator I/O.
"""

from __future__ import annotations

import hashlib
import json
import platform
from pathlib import Path

try:
    import session_evidence as _sev
except ImportError:  # builder imported without the screenshots path first
    import sys as _sys

    _sys.path.insert(
        0, str(Path(__file__).resolve().parent.parent / "screenshots"))
    import session_evidence as _sev

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError as exc:  # fail loudly, never silently degrade rendering
    raise SystemExit(f"panels builder requires Pillow: {exc}")

try:
    import PIL as _PIL
except ImportError:  # pragma: no cover - Pillow ships __init__ with Image
    _PIL = None  # type: ignore[assignment]


# ---------------------------------------------------------------------------
# Template pins (owner-fixed; MUST NOT be altered without renewed approval)
# ---------------------------------------------------------------------------

TEMPLATE_69 = 13
TEMPLATE_IPAD = "ipad-v1"

LOCALES = ("en", "ru", "zh-Hans", "es-419", "pt-BR")

CANVAS_69 = (1320, 2868)
CANVAS_63 = (1206, 2622)
CANVAS_IPAD = (2064, 2752)

SIZES = {
    "6.9": {"canvas": CANVAS_69, "template": TEMPLATE_69},
    "6.3": {"canvas": CANVAS_63, "template": TEMPLATE_69},  # v13 scaled
    "ipad13": {"canvas": CANVAS_IPAD, "template": TEMPLATE_IPAD},
}

# 6.3 scale factors: every 6.3 layout constant derives per-axis from the
# verbatim v13 6.9 value (x * SX63, y * SY63, rounded). The canvases are
# near-identical in aspect (1320/2868 vs 1206/2622 differ by 0.06%), so
# the scaled composition is proportional, never reflowed.
SX63 = CANVAS_63[0] / CANVAS_69[0]
SY63 = CANVAS_63[1] / CANVAS_69[1]


def _qx(v: int) -> int:
    return int(round(v * SX63))


def _qy(v: int) -> int:
    return int(round(v * SY63))

# --- Matrix + bezel-asset contract (data only; rendering untouched) --------
#
# Canonical staged filenames shared by stage_bezel_assets.py (writer) and
# panels.py --render-matrix (reader). The PNG bytes themselves live in
# external retention / the private versioned release, never in git.
# Staged filenames are stable across the Figma→Apple migration so matrix
# readers and existing tests keep working; only the verified artwork
# behind them changes (see APPLE_* pins below).
BEZEL_FILE_69 = "iphone-69-bezel.png"
BEZEL_FILE_63 = "iphone-63-bezel.png"
BEZEL_FILE_IPAD = "ipad-13-bezel.png"
BEZEL_FILES = {"6.9": BEZEL_FILE_69, "6.3": BEZEL_FILE_63,
               "ipad13": BEZEL_FILE_IPAD}

# Official Apple device-art pins (tasks 10.1; release apple-bezels-v2).
# The release manifest is verified by exact SHA256 BEFORE any of its
# metadata is used (see stage_bezel_assets.py); per-asset bytes are then
# verified against the manifest SHA256 plus the native geometry/cavity
# below. Never trust a downloaded manifest's mutable SHA claims, never
# extract from DMGs, never call design-service APIs. Mask radii are
# circle-fitted from the exact original alpha (17 Pro Max 192, 18 Pro Max
# 192, 17 190 — near-identical 3x corner units; iPad keeps the
# long-standing 56, whose dims/cavity already fit the M5 art byte-for-byte
# in profile). v1 pins stay for historical bundles already staged — new
# staging pins v2 (see APPLE_MANIFEST_SHA256 default in the stager).
APPLE_RELEASE = "apple-bezels-v2"
APPLE_RELEASE_V1 = "apple-bezels-v1"
APPLE_RELEASE_REPO = "AntonKosenkoPro/lifio-design-assets"
APPLE_MANIFEST_NAME = "apple-bezels-manifest.json"
APPLE_MANIFEST_SHA256 = (
    "c8d0ce9f2213872794a51960600755e668d9666f078cf7eb7b0ba6e5c28ae817")
APPLE_MANIFEST_SHA256_V1 = (
    "a9b21ed835d7a231088e2a3249e8cfcc42b92162dfec3dcbc870c34ee6affaad")
APPLE_ASSET_69 = "iphone-17-pro-max-silver-portrait.png"
APPLE_ASSET_18PM = "iphone-18-pro-max-silver-portrait.png"
APPLE_ASSET_63 = "iphone-17-white-portrait.png"
APPLE_ASSET_IPAD = "ipad-pro-m5-13inch-silver-portrait.png"
APPLE_SOURCE_69 = {
    "name": APPLE_ASSET_69,
    "sha256": "171f0a393dc89af4b7d72ba13fe0faa210adec904debcb1657abade46d52792a",
    "native": (1470, 3000),
    "slot": (1320, 2868),
    "at": (75, 66),
    "mask_r": 192,
    "model": "iPhone 17 Pro Max",
    "color": "Silver",
    "profile": "apple-17pm-v1",
}
APPLE_SOURCE_18PM = {
    "name": APPLE_ASSET_18PM,
    "sha256": "6cb9e72efb88c172710d0388f63f51fad883c86895ee382fb402559c0315343d",
    "native": (1470, 3000),
    "slot": (1320, 2868),
    "at": (75, 66),
    "mask_r": 192,
    "model": "iPhone 18 Pro Max",
    "color": "Silver",
    "profile": "apple-18pm-v1",
}
APPLE_SOURCE_63 = {
    "name": APPLE_ASSET_63,
    "sha256": "fb93a0b6e95e8c3c5ad923a8437e598746f5d4fa63ea971650172cb93727006a",
    "native": (1350, 2760),
    "slot": (1206, 2622),
    "at": (72, 69),
    "mask_r": 190,
    "model": "iPhone 17",
    "color": "White",
    "profile": "apple-17-v1",
}
APPLE_SOURCE_IPAD = {
    "name": APPLE_ASSET_IPAD,
    "sha256": "0565de2da914c2b289074941c4c1d3ff04d2aad71d2ec27ec67a7876074c4024",
    "native": (2300, 3000),
    "slot": (2064, 2752),
    "at": (118, 124),
    "mask_r": 56,
    "model": "iPad Pro (M5) 13-inch",
    "color": "Silver",
    "profile": "apple-m5-v1",
}
# Per-size preferred release asset when one manifest lists several
# same-geometry candidates (v2 carries the 17PM file for history next to
# the current 18PM file). A sole candidate stages as-is (v1 manifests
# keep working); competing non-preferred candidates refuse (never pick or
# merge silently).
APPLE_PREFERRED_ASSET = {
    "6.9": APPLE_ASSET_18PM,
    "6.3": APPLE_ASSET_63,
    "ipad13": APPLE_ASSET_IPAD,
}
# Legacy Figma profile for the frozen v13 evidence path (retained
# byte-identical fixtures only — never staged for new renders).
LEGACY_BEZEL_PROFILE_69 = "figma-v13"
STAGE_MANIFEST_FILE = "bezel-stage.json"

# CI device keys (see the app-screenshots workflow device catalog) mapped
# to the panel size contract. Owner lineup: iPhone 18 Pro Max Silver
# (iphone69), iPhone 17 White (iphone63), iPad Pro 13-inch (M5) Silver
# (ipad13) — iphone65 was dropped, so the catalog holds exactly these
# three. Model/color/Apple-asset descriptions are informational
# only (rendering keys stay size/canvas/island); actual SDK identifiers
# are aligned by the source catalog owner separately, never guessed here.
# Unknown keys stay BLOCKED at the catalog gate in panels.py (recorded,
# never rendered, never stretched).
MATRIX_DEVICES = {
    "iphone69": {"size": "6.9", "canvas": (1320, 2868), "island": True,
                 "model": "iPhone 18 Pro Max", "color": "Silver",
                 "apple_asset": APPLE_ASSET_18PM},
    "iphone63": {"size": "6.3", "canvas": (1206, 2622), "island": True,
                 "model": "iPhone 17", "color": "White",
                 "apple_asset": APPLE_ASSET_63},
    "ipad13": {"size": "ipad13", "canvas": (2064, 2752), "island": False,
               "model": "iPad Pro (M5) 13-inch", "color": "Silver",
               "apple_asset": APPLE_ASSET_IPAD},
}

ACCENT = (0x0A, 0x84, 0xFF)
WHITE = (255, 255, 255)
BG_TOL = 20

# Owner-fixed EN copy, verbatim (v13 COPY) — MUST NOT be altered.
EN_FLAT = {
    "track": "Time tracking at your fingertips.",
    "insights": "See where your time goes.",
    "history_primary": "Every minute, at a glance.",
    "history_secondary": "For your eyes only.",
    "live_activity": "Your timer, always in view.",
    "add_entry": "All details you need.",
}

# Fixed point sizes per panel key: (size_pt, bold, gap_after_px).
TYPE_69 = {
    "track": [(96, True, 0)],
    "insights": [(96, True, 0)],
    "history": [(92, True, 10), (52, False, 0)],
    "add-entry": [(96, True, 0)],
    "la": [(92, True, 0)],
}
# ipad-v1 uses the same point sizes as v13 so copy treatment is identical.
TYPE_IPAD = {
    "track": [(96, True, 0)],
    "insights": [(96, True, 0)],
    "history": [(92, True, 10), (52, False, 0)],
    "add-entry": [(96, True, 0)],
}

CAPTION_KEYS = ("track", "insights", "history_primary", "history_secondary",
                "live_activity", "add_entry")

# Panel key -> source frame(s). LA-combined is iPhone-only.
PANEL_FRAMES_69 = {
    "track": ("track-running",),
    "insights": ("insights",),
    "history": ("history",),
    "add-entry": ("add-entry",),
    "la": ("la-lock", "la-compact", "la-expanded"),
}
PANEL_FRAMES_IPAD = {
    "track": "track-running",
    "insights": "insights",
    "history": "history",
    "add-entry": "add-entry",
}
NEEDED_FRAMES_69 = ("track-running", "insights", "history", "add-entry",
                    "la-lock", "la-compact", "la-expanded")

PANEL_FILE_WORD = {
    "track": "track",
    "insights": "insights",
    "history": "history",
    "add-entry": "add-entry",
    "la": "live-activities",
}

# Approved-template output hashes: EN builds from approved sources MUST
# reproduce these exactly (byte-identical proof, enforced --check-template).
EXPECTED_EN69 = {
    "track": "4b2cd174c03fe5634a2b6bdc78ccc3a207af798d4e2da8e6145f5067549680bc",
    "insights": "8d541a257872391be518229000b0d2ad075a66c4deeb0a38d8fa5f35f8a971b1",
    "history": "f031d0502ac13bc2f635bb03ea5106c940547ab041926a0aeb6dc6d94926f40e",
    "add-entry": "9f184ecf665fcd6e2fbc38607b30791b0cd53fbeb8600c7e6bde0db3579a15e2",
    "la": "6700374bb103bd707446a261d2410745e81b6aae1362a82a01ed4de961fa3d91",
}
EXPECTED_EN_IPAD = {
    "track": "1f9b28a540660c7c920d90124b22ab760752fb692c7a00a60b4481ccd16ec97d",
    "insights": "92db0a732bdcd0ae1f3cce39d4542775423622987a7d8ec13610248b8b13e5b1",
    "history": "3d723fa0d95805c53582723fa0308650e788cadb5bcebb935046422d885d26c9",
    "add-entry": "a71feb2d2ae9653236d9fadfd0bfa0ddfc0cc689447e2a535cf1fb843ee5e053",
}

REVIEW_STATUS = (
    "REVIEW SET ONLY — composition review, NOT a Store deliverable, NOT "
    "counted toward the 70-image matrix; matrix render stays HELD per 9.3 "
    "(chrome-fixed sources verified frame-by-frame + retaken-set "
    "re-approval (5.4) required before any 9.x approval gate)."
)

# --- 6.9 / v13 geometry (verbatim from build_final_v13.py) -----------------

HEADLINE_MAX_W_69 = 1140
HEADLINE_TOP_MARGIN_69 = 168
MIN_GAP_69 = 70

BEZEL69_NATIVE = (980, 2000)
BEZEL69_SLOT = (880, 1912)
BEZEL69_AT = (50, 44)
BEZEL69_MASK_R = 120

DEVICE_W_69 = 1152
DEVICE_BACK_W_69 = 992

HISTORY_SHOT_TOP_69 = 444
ADD_ENTRY_SHOT_TOP_69 = 444

BANNER_SRC_TOP = 2270
BANNER_SRC_BOTTOM = 2458

# v11 owner-Figma LA geometry, verbatim (outer px).
TOP_BOX_FIGMA = [82, -1176, 1234, 1175]
HEADLINE_BOX_FIGMA = [1276, 1486]
BACK_BOX_FIGMA = [162, 1587, 1154, 3611]
FRONT_BOX_FIGMA = [84, 1742, 1236, 4093]

# --- 6.3 / v13-scaled geometry (derived, never hand-tuned) -------------------
#
# Every value below is the v13 6.9 constant scaled per-axis (_qx/_qy).
# Device-box heights are NOT pinned here: they follow the measured bezel
# aspect at render time (aspect_h_63), so a Figma export whose frame ratio
# differs slightly from 980:2000 still composes instead of failing on a
# rounding pixel. Widths, origins, headline boxes, and banner source rows
# stay pinned to the scaled derivation; the LA builder re-checks all
# gap/overlap/bleed invariants on the derived boxes.
HEADLINE_MAX_W_63 = _qx(HEADLINE_MAX_W_69)
HEADLINE_TOP_MARGIN_63 = _qy(HEADLINE_TOP_MARGIN_69)
MIN_GAP_63 = _qy(MIN_GAP_69)

DEVICE_W_63 = _qx(DEVICE_W_69)
DEVICE_BACK_W_63 = _qx(DEVICE_BACK_W_69)

HISTORY_SHOT_TOP_63 = _qy(HISTORY_SHOT_TOP_69)
ADD_ENTRY_SHOT_TOP_63 = _qy(ADD_ENTRY_SHOT_TOP_69)

BANNER_SRC_TOP_63 = _qy(BANNER_SRC_TOP)
BANNER_SRC_BOTTOM_63 = _qy(BANNER_SRC_BOTTOM)

TOP_BOX_63 = [_qx(TOP_BOX_FIGMA[0]), _qy(TOP_BOX_FIGMA[1]),
              _qx(TOP_BOX_FIGMA[2]), None]  # y1 follows bezel aspect
HEADLINE_BOX_63 = [_qy(HEADLINE_BOX_FIGMA[0]), _qy(HEADLINE_BOX_FIGMA[1])]
BACK_BOX_63 = [_qx(BACK_BOX_FIGMA[0]), _qy(BACK_BOX_FIGMA[1]),
               _qx(BACK_BOX_FIGMA[2]), None]
FRONT_BOX_63 = [_qx(FRONT_BOX_FIGMA[0]), _qy(FRONT_BOX_FIGMA[1]),
                _qx(FRONT_BOX_FIGMA[2]), None]

# Scaled type table: same caption binding as v13, point sizes via _qx
# (width is the constraining axis), line gaps via _qy.
TYPE_63 = {
    "track": [(_qx(96), True, 0)],
    "insights": [(_qx(96), True, 0)],
    "history": [(_qx(92), True, _qy(10)), (_qx(52), False, 0)],
    "add-entry": [(_qx(96), True, 0)],
    "la": [(_qx(92), True, 0)],
}

# 6.3 bezel acceptance (structural — exact pixels are NOT pinned):
# portrait PNG with alpha, sane size, a dominant transparent slot whose
# aspect agrees with the 1206x2622 canvas, opaque frame samples.
BEZEL63_MIN_DIM = 400
BEZEL63_MAX_DIM = 4000
BEZEL63_MIN_MARGIN = 8
BEZEL63_MIN_SLOT_FRAC = 0.5
BEZEL63_MAX_ASPECT_DEV = 0.01  # 1%: catches wrong-device bezels, allows export rounding
BEZEL63_MIN_SLOT_CLEAR_FRAC = 0.97  # slot holds the Island pill + AA edges (6.9 measures 0.984)

FONT_HEL = "/System/Library/Fonts/Helvetica.ttc"
FONT_HIRA = "/System/Library/Fonts/Hiragino Sans GB.ttc"
HEL_BOLD_IDX, HEL_REG_IDX = 1, 0
HIRA_BOLD_IDX, HIRA_REG_IDX = 1, 0  # W6 headline-bold / W3 regular

# --- iPad / ipad-v1 geometry (verbatim from build_ipad_panels_v1.py) --------

BEZEL_IPAD_NATIVE = (2300, 3000)
CAVITY_AT = (118, 124)
CAVITY_SIZE = (2064, 2752)
CAVITY_R = 56

HEADLINE_MAX_W_IPAD = 1820
HEADLINE_TOP_MARGIN_IPAD = 168
MIN_GAP_IPAD = 70
BOTTOM_MIN_IPAD = 40
SIDE_MIN_IPAD = 96
SHADOW_R_IPAD = 200
SHADOW_BLUR_IPAD = 55


class BuilderError(ValueError):
    """Fail-closed builder error: invalid input, not a renderable finding."""


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# Captions
# ---------------------------------------------------------------------------

def load_captions(path: Path) -> dict:
    """Load + schema-check a captions file (captions-v1 schema)."""
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise BuilderError(f"captions file not readable {path}: {exc}")
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuilderError(f"captions file malformed {path}: {exc}")
    if not isinstance(obj, dict):
        raise BuilderError("captions file must contain a JSON object")
    caps = obj.get("captions")
    if not isinstance(caps, dict):
        raise BuilderError("captions file missing 'captions' object")
    for key in CAPTION_KEYS:
        entry = caps.get(key)
        if not isinstance(entry, dict):
            raise BuilderError(f"captions missing key {key!r}")
        for field in ("text", "en"):
            val = entry.get(field)
            if not isinstance(val, str) or not val:
                raise BuilderError(f"captions.{key}.{field} must be a non-empty string")
    return obj


def validate_captions_for_locale(obj: dict, locale: str) -> dict:
    """Fail-closed caption checks: locale match + verbatim EN reference."""
    if obj.get("locale") != locale:
        raise BuilderError(
            f"captions locale {obj.get('locale')!r} != requested locale {locale!r}; "
            "no cross-locale caption mixing")
    caps = obj["captions"]
    for key, want in (("track", EN_FLAT["track"]),
                      ("insights", EN_FLAT["insights"]),
                      ("history_primary", EN_FLAT["history_primary"]),
                      ("history_secondary", EN_FLAT["history_secondary"]),
                      ("live_activity", EN_FLAT["live_activity"]),
                      ("add_entry", EN_FLAT["add_entry"])):
        got = caps[key]["en"]
        if got != want:
            raise BuilderError(
                f"captions.{key}.en drift vs owner-fixed copy: {got!r} != {want!r}; "
                "altered English copy fails validation — renewed owner approval required")
    if locale == "en":
        pairs = (("track", EN_FLAT["track"]), ("insights", EN_FLAT["insights"]),
                 ("history_primary", EN_FLAT["history_primary"]),
                 ("history_secondary", EN_FLAT["history_secondary"]),
                 ("live_activity", EN_FLAT["live_activity"]),
                 ("add_entry", EN_FLAT["add_entry"]))
        for key, want in pairs:
            if caps[key]["text"] != want:
                raise BuilderError(
                    f"en captions.{key}.text drift vs owner-fixed copy: "
                    f"{caps[key]['text']!r} != {want!r}")
    return caps


def _with_texts(table: dict, texts: dict) -> dict:
    """Bind caption texts to the FIXED (size_pt, bold, gap) type table."""
    return {key: [(text,) + tuple(spec)
                  for text, spec in zip(texts[key], table[key])]
            for key in table}


def copy_for_69(caps: dict) -> dict:
    """Panel copy with FIXED v13 point sizes (typography never scales)."""
    return _with_texts(TYPE_69, {
        "track": [caps["track"]["text"]],
        "insights": [caps["insights"]["text"]],
        "history": [caps["history_primary"]["text"],
                    caps["history_secondary"]["text"]],
        "add-entry": [caps["add_entry"]["text"]],
        "la": [caps["live_activity"]["text"]],
    })


def copy_for_ipad(caps: dict) -> dict:
    """Panel copy with FIXED ipad-v1 point sizes (identical to v13)."""
    return _with_texts(TYPE_IPAD, {
        "track": [caps["track"]["text"]],
        "insights": [caps["insights"]["text"]],
        "history": [caps["history_primary"]["text"],
                    caps["history_secondary"]["text"]],
        "add-entry": [caps["add_entry"]["text"]],
    })


def copy_for_63(caps: dict) -> dict:
    """Panel copy with SCALED v13 point sizes (TYPE_63 derives from v13)."""
    return _with_texts(TYPE_63, {
        "track": [caps["track"]["text"]],
        "insights": [caps["insights"]["text"]],
        "history": [caps["history_primary"]["text"],
                    caps["history_secondary"]["text"]],
        "add-entry": [caps["add_entry"]["text"]],
        "la": [caps["live_activity"]["text"]],
    })


# ---------------------------------------------------------------------------
# Fonts + text (EN path is behavior-identical to build_final_v13.py)
# ---------------------------------------------------------------------------

def font_for(locale: str, size: int, bold: bool) -> ImageFont.FreeTypeFont:
    if locale == "zh-Hans":
        # Helvetica carries no CJK (probed in the final-panels lineage:
        # every CJK glyph missing) — Hiragino Sans GB carries the set.
        # Missing font fails loudly here, never silently tofu-renders.
        try:
            return ImageFont.truetype(FONT_HIRA, size,
                                      index=HIRA_BOLD_IDX if bold else HIRA_REG_IDX)
        except OSError as exc:
            raise BuilderError(f"zh-Hans font unreadable {FONT_HIRA}: {exc}")
    try:
        return ImageFont.truetype(FONT_HEL, size,
                                  index=HEL_BOLD_IDX if bold else HEL_REG_IDX)
    except OSError as exc:
        raise BuilderError(f"headline font unreadable {FONT_HEL}: {exc}")


def font_label(locale: str, bold: bool) -> str:
    if locale == "zh-Hans":
        return "HiraginoSansGB-W6" if bold else "HiraginoSansGB-W3"
    return "Helvetica-Bold" if bold else "Helvetica"


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont,
         max_w: int) -> list[str]:
    if " " not in text:
        # CJK: character-level wrap (no spaces to split on).
        lines, cur = [], ""
        for ch in text:
            if draw.textlength(cur + ch, font=fnt) <= max_w or not cur:
                cur += ch
            else:
                lines.append(cur)
                cur = ch
        lines.append(cur)
        return lines
    words, lines, cur = text.split(" "), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=fnt) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def headline_height_69(locale: str,
                       lines_cfg: list[tuple[str, int, bool, int]]) -> int:
    probe = Image.new("RGB", (8, 8))
    d = ImageDraw.Draw(probe)
    h = 0
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_69):
            asc, desc = fnt.getmetrics()
            h += asc + desc + 6
        h += gap
    return h


def headline_height_ipad(locale: str,
                         lines_cfg: list[tuple[str, int, bool, int]]) -> int:
    probe = Image.new("RGB", (8, 8))
    d = ImageDraw.Draw(probe)
    h = 0
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_IPAD):
            asc, desc = fnt.getmetrics()
            h += asc + desc + 6
        h += gap
    return h


def draw_headline_69(base: Image.Image, locale: str,
                     lines_cfg: list[tuple[str, int, bool, int]],
                     y_top: int) -> tuple[int, int]:
    d = ImageDraw.Draw(base)
    y = y_top
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_69):
            asc, desc = fnt.getmetrics()
            d.text((CANVAS_69[0] // 2, y), ln, font=fnt, fill=WHITE, anchor="ma")
            y += asc + desc + 6
        y += gap
    return y_top, y


def draw_headline_centered_69(base: Image.Image, locale: str,
                              lines_cfg: list[tuple[str, int, bool, int]],
                              band: list[int]) -> tuple[int, int]:
    h = headline_height_69(locale, lines_cfg)
    if h > band[1] - band[0]:
        raise BuilderError(
            f"headline text {h}px taller than Figma band {band[1] - band[0]}px "
            f"({band}); caption does not fit the approved LA template — "
            "9.2 finding, never silently shrunk")
    y = band[0] + (band[1] - band[0] - h) // 2
    top = y
    d = ImageDraw.Draw(base)
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_69):
            asc, desc = fnt.getmetrics()
            d.text((CANVAS_69[0] // 2, y), ln, font=fnt, fill=WHITE, anchor="ma")
            y += asc + desc + 6
        y += gap
    return top, top + h


def draw_headline_ipad(base: Image.Image, locale: str,
                       lines_cfg: list[tuple[str, int, bool, int]],
                       y_top: int) -> tuple[int, int]:
    d = ImageDraw.Draw(base)
    y = y_top
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        rendered = wrap(d, text, fnt, HEADLINE_MAX_W_IPAD)
        for ln in rendered:
            asc, desc = fnt.getmetrics()
            d.text((CANVAS_IPAD[0] // 2, y), ln, font=fnt, fill=WHITE, anchor="ma")
            y += asc + desc + 6
        y += gap
    return y_top, y


def headline_height_63(locale: str,
                       lines_cfg: list[tuple[str, int, bool, int]]) -> int:
    probe = Image.new("RGB", (8, 8))
    d = ImageDraw.Draw(probe)
    h = 0
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_63):
            asc, desc = fnt.getmetrics()
            h += asc + desc + 6
        h += gap
    return h


def draw_headline_63(base: Image.Image, locale: str,
                     lines_cfg: list[tuple[str, int, bool, int]],
                     y_top: int) -> tuple[int, int]:
    d = ImageDraw.Draw(base)
    y = y_top
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_63):
            asc, desc = fnt.getmetrics()
            d.text((CANVAS_63[0] // 2, y), ln, font=fnt, fill=WHITE, anchor="ma")
            y += asc + desc + 6
        y += gap
    return y_top, y


def draw_headline_centered_63(base: Image.Image, locale: str,
                              lines_cfg: list[tuple[str, int, bool, int]],
                              band: list[int]) -> tuple[int, int]:
    h = headline_height_63(locale, lines_cfg)
    if h > band[1] - band[0]:
        raise BuilderError(
            f"headline text {h}px taller than scaled band {band[1] - band[0]}px "
            f"({band}); caption does not fit the scaled LA template — "
            "9.2 finding, never silently shrunk")
    y = band[0] + (band[1] - band[0] - h) // 2
    top = y
    d = ImageDraw.Draw(base)
    for text, size, bold, gap in lines_cfg:
        fnt = font_for(locale, size, bold)
        for ln in wrap(d, text, fnt, HEADLINE_MAX_W_63):
            asc, desc = fnt.getmetrics()
            d.text((CANVAS_63[0] // 2, y), ln, font=fnt, fill=WHITE, anchor="ma")
            y += asc + desc + 6
        y += gap
    return top, top + h


# ---------------------------------------------------------------------------
# Source + bezel verification (fail-closed; no stretching, no tampering)
# ---------------------------------------------------------------------------

def verify_sources(frames_dir: Path, manifest_path: Path,
                   needed: tuple[str, ...],
                   canvas: tuple[int, int],
                   evidence_frames: tuple[str, ...] | None = None
                   ) -> tuple[dict, dict]:
    try:
        manifest = json.loads(manifest_path.read_bytes().decode("utf-8"))
    except OSError as exc:
        raise BuilderError(f"run manifest not readable {manifest_path}: {exc}")
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuilderError(f"run manifest malformed {manifest_path}: {exc}")
    if not isinstance(manifest, dict) or not isinstance(manifest.get("frames"), list):
        raise BuilderError(f"run manifest {manifest_path} missing 'frames' list")
    # Strict shared-helper evidence first (single chokepoint owned by the
    # runner; never reimplemented here): session nonce/transcript coverage,
    # combined app/host receipt, path/symlink guards, attested N/A probe
    # binding (run/device/geometry/model/source/realtime-nonce),
    # fabrication and required-lock handling. required_frames = filed
    # manifest entries plus the evidence set, so fabricated island entries
    # are validated (and refused) by the helper too; the complete-set gate
    # below (status == complete) stays unchanged so pending LA still blocks
    # the whole cell.
    run_dir = manifest_path.parent
    manifest_frames = [r.get("frame") for r in manifest.get("frames", [])
                       if isinstance(r, dict)
                       and isinstance(r.get("frame"), str)]
    evidence = list(evidence_frames) if evidence_frames is not None \
        else list(needed)
    required = list(dict.fromkeys([*manifest_frames, *evidence]))
    try:
        evidence_errs = _sev.validate_run_evidence(
            run_dir, manifest, required_frames=required)
    except Exception as exc:
        raise BuilderError(
            f"session evidence unreadable for {manifest_path}: {exc}")
    if evidence_errs:
        first = evidence_errs[0]
        extra = f" (+{len(evidence_errs) - 1} more)" if len(
            evidence_errs) > 1 else ""
        raise BuilderError(
            f"session evidence refused for {manifest_path}: "
            f"{first}{extra}")
    if manifest.get("status") != "complete":
        raise BuilderError(
            f"run {manifest.get('run_id')} status {manifest.get('status')!r} != "
            "'complete'; blocked set — record the finding, never render it")
    by_frame = {f.get("frame"): f for f in manifest["frames"]
                if isinstance(f, dict)}
    ok: dict = {}
    for frame in needed:
        entry = by_frame.get(frame)
        if entry is None:
            raise BuilderError(
                f"required source frame {frame!r} missing from run manifest "
                f"{manifest_path}; set incomplete — recorded, never fabricated")
        png = frames_dir / f"{frame}.png"
        if not png.is_file():
            raise BuilderError(f"missing source PNG {png}")
        actual = sha(png)
        if actual != entry.get("screenshot_sha256"):
            raise BuilderError(
                f"source hash drift {frame}: file {actual[:12]} != manifest "
                f"{str(entry.get('screenshot_sha256'))[:12]}; recapture "
                "invalidates the panel input")
        geo = entry.get("geometry", {})
        if (geo.get("width"), geo.get("height")) != (canvas[0], canvas[1]):
            raise BuilderError(
                f"source geometry drift {frame}: {(geo.get('width'), geo.get('height'))} "
                f"!= canvas {canvas}; no cross-size stretching")
        ok[frame] = entry["screenshot_sha256"]
    meta = {"run_id": manifest.get("run_id"),
            "deck_version": manifest.get("deck_version"),
            "treatment": manifest.get("treatment"),
            "status": manifest.get("status")}
    return ok, meta


def _check_opaque_frame_strip(a, x0: int, y0: int, sw: int, sh: int,
                              size: tuple[int, int]) -> None:
    """Require opaque bezel frame beside the cavity (alpha-only samples).

    Samples a vertical strip left of the cavity at mid-height and a
    horizontal strip above it at quarter width — both clear of rounded
    outer corners. Missing on both strips means no surrounding frame.
    """
    w, h = size
    mid_y = y0 + sh // 2
    strip_x = max(0, x0 // 2)
    left_ok = any(
        a.getpixel((strip_x, y)) == 255
        for y in range(mid_y - 40, mid_y + 41, 4))
    top_y = max(0, y0 // 2)
    top_ok = any(
        a.getpixel((x, top_y)) == 255
        for x in range(w // 4 - 40, w // 4 + 41, 4))
    if not (left_ok or top_ok):
        raise BuilderError(
            "bezel frame missing beside the slot "
            f"(opaque frame not found near {(strip_x, mid_y)} or "
            f"{(w // 4, top_y)})")


def _check_cavity_interior_clear(a, x0: int, y0: int, sw: int, sh: int,
                                 margin: int, what: str) -> None:
    """Require the cavity interior (inside the mask margin) fully clear.

    RGB is deliberately ignored — official art ships transparent WHITE in
    some cavities and transparent BLACK in others; only alpha binds.
    """
    for y in range(y0 + margin, y0 + sh - margin, 7):
        for x in range(x0 + margin, x0 + sw - margin, 11):
            if a.getpixel((x, y)) != 0:
                raise BuilderError(
                    f"{what} cavity interior not transparent "
                    f"(alpha {a.getpixel((x, y))} at {(x, y)}); refusing "
                    "to render into an obstructed cavity")


def verify_bezel_69(bezel_path: Path) -> dict:
    """Exact-profile verification for the 6.9 iPhone bezel (new art + legacy).

    Apple profiles (tasks 10.x): exact 1470x3000 native art, measured slot
    exactly 1320x2868@(75,66), clear interior, opaque surrounding frame.
    The profile resolves by exact bytes — `apple-18pm-v1` for the pinned
    18PM file, `apple-17pm-v1` for the pinned 17PM file (same slot,
    pill art differs); geometry-matched unpinned art (synthetic fixtures
    only) reports the 17PM lineage profile. Legacy Figma profile
    (`figma-v13`): the frozen 980x2000 / 880x1912@(50,44) thresholds,
    unchanged, for the retained v13 byte-identical evidence path only.
    Anything else fails closed.
    """
    if not bezel_path.is_file():
        raise BuilderError(f"missing bezel asset {bezel_path}")
    with Image.open(bezel_path) as im:
        size, bands, mode = tuple(im.size), im.getbands(), im.mode
        if "A" not in bands:
            raise BuilderError(
                "bezel must carry alpha (transparent screen)")
        a = im.getchannel("A")
        a.load()
        extrema = a.getextrema()
    if size == tuple(APPLE_SOURCE_69["native"]):
        file_sha = sha(bezel_path)
        pins = {APPLE_SOURCE_69["sha256"]: APPLE_SOURCE_69,
                APPLE_SOURCE_18PM["sha256"]: APPLE_SOURCE_18PM}.get(
                    file_sha, APPLE_SOURCE_69)
        slot, at = tuple(pins["slot"]), tuple(pins["at"])
        measured_slot, measured_at = detect_bezel_slot(bezel_path)
        if tuple(measured_slot) != slot or tuple(measured_at) != at:
            raise BuilderError(
                f"bezel screen slot drift {measured_slot}@{measured_at} != "
                f"pinned {slot}@{at}; no silent scale/rotate")
        if slot[0] * CANVAS_69[1] != slot[1] * CANVAS_69[0]:
            raise BuilderError("screen slot aspect drift vs canvas")
        if at[0] + slot[0] > size[0] or at[1] + slot[1] > size[1]:
            raise BuilderError("screen slot overflow")
        with Image.open(bezel_path) as im:
            a = im.getchannel("A")
            a.load()
            _check_cavity_interior_clear(
                a, at[0], at[1], slot[0], slot[1],
                pins["mask_r"], pins["profile"])
            _check_opaque_frame_strip(a, at[0], at[1], slot[0], slot[1],
                                      size)
        return {"sha256": file_sha, "size": list(size), "mode": mode,
                "profile": pins["profile"],
                "screen_slot_px": list(slot), "screen_at_px": list(at),
                "screen_mask_radius_px": pins["mask_r"]}
    if size == BEZEL69_NATIVE:
        sw, sh = BEZEL69_SLOT
        if (sw, sh) != (880, 1912):
            raise BuilderError("screen slot drift")
        if sw * CANVAS_69[1] != sh * CANVAS_69[0]:
            raise BuilderError("screen slot aspect drift")
        x, y = BEZEL69_AT
        if x + sw > BEZEL69_NATIVE[0] or y + sh > BEZEL69_NATIVE[1]:
            raise BuilderError("screen slot overflow")
        return {"sha256": sha(bezel_path), "size": list(size), "mode": mode,
                "profile": LEGACY_BEZEL_PROFILE_69,
                "screen_slot_px": list(BEZEL69_SLOT),
                "screen_at_px": list(BEZEL69_AT),
                "screen_mask_radius_px": BEZEL69_MASK_R}
    raise BuilderError(
        f"bezel size drift {size} != apple {tuple(APPLE_SOURCE_69['native'])} "
        f"or legacy {BEZEL69_NATIVE}; no silent scale/rotate")


def verify_bezel_ipad(bezel_path: Path) -> dict:
    if not bezel_path.is_file():
        raise BuilderError(f"missing bezel asset {bezel_path}")
    with Image.open(bezel_path) as im:
        size, bands, mode = tuple(im.size), im.getbands(), im.mode
        a = im.getchannel("A")
        a.load()
        interior = a.crop((CAVITY_AT[0] + CAVITY_R, CAVITY_AT[1] + CAVITY_R,
                           CAVITY_AT[0] + CAVITY_SIZE[0] - CAVITY_R,
                           CAVITY_AT[1] + CAVITY_SIZE[1] - CAVITY_R))
        interior_extrema = interior.getextrema()
        edge_l = a.crop((0, 900, CAVITY_AT[0], 2100))
        edge_max = edge_l.getextrema()[1]
    if size != BEZEL_IPAD_NATIVE:
        raise BuilderError(f"bezel size drift {size} != {BEZEL_IPAD_NATIVE}")
    if "A" not in bands:
        raise BuilderError("bezel must carry alpha (transparent screen)")
    cx, cy = CAVITY_AT
    cw, ch = CAVITY_SIZE
    if cx + cw > size[0] or cy + ch > size[1]:
        raise BuilderError("cavity overflow")
    if interior_extrema != (0, 0):
        raise BuilderError("cavity interior not transparent")
    if edge_max != 255:
        raise BuilderError("left bezel frame missing")
    return {"sha256": sha(bezel_path), "size": list(size), "mode": mode,
            "cavity_at": list(CAVITY_AT), "cavity_size": list(CAVITY_SIZE)}


def _longest_zero_run(vals: list[int]) -> tuple[int, int] | None:
    """Longest contiguous alpha==0 run as (start, end) inclusive."""
    best: tuple[int, int] | None = None
    blen = -1
    s: int | None = None
    for i, v in enumerate(vals):
        if v == 0 and s is None:
            s = i
        if v != 0 and s is not None:
            if i - s > blen:
                best, blen = (s, i - 1), i - s
            s = None
    if s is not None and len(vals) - s > blen:
        best = (s, len(vals) - 1)
    return best


def detect_bezel_slot(bezel_path: Path) -> tuple[tuple[int, int],
                                                 tuple[int, int]]:
    """Measure the transparent screen slot ((w, h), (x, y)) from alpha.

    Row scan at mid-height gives the slot width (below the Island pill);
    column scans at the quarter widths give the full slot height (clear of
    the centered pill). The two column runs must agree: a skewed or
    multi-cavity file fails loudly instead of rendering off-center art.
    Probed against the retained 6.9 bezel: returns exactly ((880, 1912),
    (50, 44)). Against the official Apple art it returns the exact pinned
    cavities: 17 Pro Max ((1320, 2868), (75, 66)), 17 ((1206, 2622),
    (72, 69)), iPad M5 ((2064, 2752), (118, 124)).
    """
    with Image.open(bezel_path) as im:
        w, h = im.size
        a = im.getchannel("A")
        a.load()
        row = [a.getpixel((x, h // 2)) for x in range(w)]
        col_l = [a.getpixel((w // 4, y)) for y in range(h)]
        col_r = [a.getpixel((3 * w // 4, y)) for y in range(h)]
    x_run = _longest_zero_run(row)
    yl_run = _longest_zero_run(col_l)
    yr_run = _longest_zero_run(col_r)
    if x_run is None or yl_run is None or yr_run is None:
        raise BuilderError(
            f"bezel {bezel_path} has no transparent screen slot; refusing "
            "to fabricate device art")
    if yl_run != yr_run:
        raise BuilderError(
            f"bezel slot asymmetric (left {yl_run} != right {yr_run}); "
            "refusing to render into an unverified cavity")
    (x0, x1), (y0, y1) = x_run, yl_run
    return (x1 - x0 + 1, y1 - y0 + 1), (x0, y0)


def verify_bezel_63(bezel_path: Path) -> dict:
    """Verification for the 6.3 iPhone bezel (two profiles).

    Apple profile (`apple-17-v1`, tasks 10.x): exact 1350x2760 native
    art with the measured slot exactly 1206x2622@(72,69) — a 1:1 native
    paste, never resampled. Anything else portrait takes the legacy
    structural path below (thresholds unchanged): the slot is measured
    via detect_bezel_slot and must dominate the frame, agree with the
    1206x2622 canvas aspect within 1%, and read >=97% clear; an opaque
    frame must surround the slot. Landscape, opaque-only, undersized, or
    aspect-drifted art fails closed on both paths.
    """
    if not bezel_path.is_file():
        raise BuilderError(f"missing bezel asset {bezel_path}")
    with Image.open(bezel_path) as im:
        size = tuple(im.size)
    if size == tuple(APPLE_SOURCE_63["native"]):
        with Image.open(bezel_path) as im:
            bands, mode = im.getbands(), im.mode
            if "A" not in bands:
                raise BuilderError(
                    "bezel must carry alpha (transparent screen)")
            a = im.getchannel("A")
            a.load()
            extrema = a.getextrema()
        if extrema[1] != 255:
            raise BuilderError("bezel frame missing (no opaque pixels)")
        slot, at = tuple(APPLE_SOURCE_63["slot"]), tuple(APPLE_SOURCE_63["at"])
        measured_slot, measured_at = detect_bezel_slot(bezel_path)
        if tuple(measured_slot) != slot or tuple(measured_at) != at:
            raise BuilderError(
                f"bezel screen slot drift {measured_slot}@{measured_at} != "
                f"pinned {slot}@{at}; no silent scale/rotate")
        if at[0] + slot[0] > size[0] or at[1] + slot[1] > size[1]:
            raise BuilderError("screen slot overflow")
        with Image.open(bezel_path) as im:
            a = im.getchannel("A")
            a.load()
            _check_cavity_interior_clear(
                a, at[0], at[1], slot[0], slot[1],
                APPLE_SOURCE_63["mask_r"], "apple-17-v1")
            _check_opaque_frame_strip(a, at[0], at[1], slot[0], slot[1],
                                      size)
            slot_alpha = a.crop((at[0], at[1],
                                 at[0] + slot[0], at[1] + slot[1]))
            slot_alpha.load()
            hist = slot_alpha.histogram()
            clear_frac = hist[0] / sum(hist)
        dev = abs(slot[0] * CANVAS_63[1] - slot[1] * CANVAS_63[0]) / (
            slot[1] * CANVAS_63[0])
        return {"sha256": sha(bezel_path), "size": list(size), "mode": mode,
                "profile": APPLE_SOURCE_63["profile"],
                "screen_slot_px": list(slot), "screen_at_px": list(at),
                "screen_mask_radius_px": APPLE_SOURCE_63["mask_r"],
                "slot_aspect_deviation": dev,
                "slot_clear_fraction": clear_frac}
    return _verify_bezel_63_structural(bezel_path)


def _verify_bezel_63_structural(bezel_path: Path) -> dict:
    """Structural verification for legacy 6.3 bezels (thresholds frozen).

    The export size is NOT guessed here: the slot is measured via
    detect_bezel_slot and must dominate the frame, agree with the
    1206x2622 canvas aspect within 1%, and read >=97% clear (the slot
    holds the opaque Island pill plus antialiased edges — the retained
    6.9 file measures 98.4%). An opaque frame must surround the slot.
    """
    if not bezel_path.is_file():
        raise BuilderError(f"missing bezel asset {bezel_path}")
    with Image.open(bezel_path) as im:
        size, bands, mode = tuple(im.size), im.getbands(), im.mode
        w, h = size
        if "A" not in bands:
            raise BuilderError("bezel must carry alpha (transparent screen)")
        if w >= h:
            raise BuilderError(
                f"bezel must be portrait, got {size}")
        if not (BEZEL63_MIN_DIM <= w <= BEZEL63_MAX_DIM
                and BEZEL63_MIN_DIM <= h <= BEZEL63_MAX_DIM):
            raise BuilderError(f"bezel size out of bounds {size}")
        a = im.getchannel("A")
        a.load()
        alpha_max = a.getextrema()[1]
    if alpha_max != 255:
        raise BuilderError("bezel frame missing (no opaque pixels)")
    (sw, sh), (x0, y0) = detect_bezel_slot(bezel_path)
    x1, y1 = x0 + sw - 1, y0 + sh - 1
    if min(x0, y0, w - 1 - x1, h - 1 - y1) < BEZEL63_MIN_MARGIN:
        raise BuilderError(
            f"bezel frame margin too small (slot at {(x0, y0)} in {size})")
    if sw * sh < BEZEL63_MIN_SLOT_FRAC * w * h:
        raise BuilderError(
            f"bezel slot too small ({(sw, sh)} in {size})")
    dev = abs(sw * CANVAS_63[1] - sh * CANVAS_63[0]) / (sh * CANVAS_63[0])
    if dev > BEZEL63_MAX_ASPECT_DEV:
        raise BuilderError(
            f"bezel slot aspect drift {(sw, sh)} vs canvas {CANVAS_63} "
            f"(deviation {dev:.4f}); no cross-size stretching")
    with Image.open(bezel_path) as im:
        a = im.getchannel("A")
        a.load()
        slot_alpha = a.crop((x0, y0, x1 + 1, y1 + 1))
        slot_alpha.load()
        hist = slot_alpha.histogram()
        clear_frac = hist[0] / sum(hist)
    if clear_frac < BEZEL63_MIN_SLOT_CLEAR_FRAC:
        raise BuilderError(
            f"bezel slot not clear (transparent fraction {clear_frac:.3f}); "
            "refusing to render into an obstructed cavity")
    # Opaque frame must surround the slot (samples clear of rounded
    # outer corners, mirroring the retained 6.9 file which reads 255).
    with Image.open(bezel_path) as im:
        a = im.getchannel("A")
        a.load()
        left_px = a.getpixel((x0 // 2, h // 2))
        top_px = a.getpixel((w // 4, y0 // 2))
    if left_px != 255 or top_px != 255:
        raise BuilderError(
            f"bezel frame missing beside the slot "
            f"(left {left_px}, top {top_px})")
    return {"sha256": sha(bezel_path), "size": list(size), "mode": mode,
            "profile": "structural-legacy",
            "screen_slot_px": [sw, sh], "screen_at_px": [x0, y0],
            "screen_mask_radius_px": mask_r_63((sw, sh)),
            "slot_aspect_deviation": dev, "slot_clear_fraction": clear_frac}


# ---------------------------------------------------------------------------
# 6.9 rendering (verbatim v13 geometry)
# ---------------------------------------------------------------------------

def load_bezel(bezel_path: Path) -> Image.Image:
    with Image.open(bezel_path) as im:
        return im.convert("RGBA")


def device_shot_69(src: Image.Image, bezel: Image.Image) -> Image.Image:
    """Composite one 1320x2868 capture into the 6.9 device art.

    Legacy Figma profile (980x2000 bezel): the frozen v13 path — the
    capture is LANCZOS-scaled to the 880x1912 slot, masked, and pasted at
    (50, 44). Apple profile (1470x3000 native art): the capture is pasted
    1:1 at the (75, 66) cavity with the measured mask radius — never
    resampled, cropped, or rotated. Any other bezel size fails closed.
    """
    if tuple(src.size) != CANVAS_69:
        raise BuilderError(
            f"cross-size art rejected: {src.size} vs canvas {CANVAS_69}")
    native, slot, at, mask_r = _shot_params_69(bezel)
    if slot == CANVAS_69:
        shot = src.convert("RGBA")
    else:
        shot = src.resize(slot, Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", slot, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, *slot], radius=mask_r, fill=255)
    shot.putalpha(mask)
    dev = Image.new("RGBA", native, (0, 0, 0, 0))
    dev.paste(shot, at, shot)
    dev.alpha_composite(bezel)
    return dev


def _shot_params_69(bezel: Image.Image
                    ) -> tuple[tuple[int, int], tuple[int, int],
                               tuple[int, int], int]:
    """(native, slot, at, mask_r) for a loaded 6.9 bezel by exact profile."""
    size = tuple(bezel.size)
    if size == tuple(APPLE_SOURCE_69["native"]):
        return (tuple(APPLE_SOURCE_69["native"]),
                tuple(APPLE_SOURCE_69["slot"]),
                tuple(APPLE_SOURCE_69["at"]),
                APPLE_SOURCE_69["mask_r"])
    if size == BEZEL69_NATIVE:
        return BEZEL69_NATIVE, BEZEL69_SLOT, BEZEL69_AT, BEZEL69_MASK_R
    raise BuilderError(
        f"unverified 6.9 bezel dimensions {size}; expected apple "
        f"{tuple(APPLE_SOURCE_69['native'])} or legacy {BEZEL69_NATIVE}")


def place_device_69(base: Image.Image, dev: Image.Image,
                    box: tuple[int, int, int, int]) -> Image.Image:
    card = Image.new("RGBA", CANVAS_69, (0, 0, 0, 0))
    sh = Image.new("RGBA", CANVAS_69, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.rounded_rectangle(box, radius=150, fill=(0, 0, 0, 90))
    card.alpha_composite(sh.filter(ImageFilter.GaussianBlur(38)))
    fitted = dev.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    card.alpha_composite(fitted, (box[0], box[1]))
    return Image.alpha_composite(base, card)


def aspect_h_69(outer_w: int) -> int:
    return round(outer_w * BEZEL69_NATIVE[1] / BEZEL69_NATIVE[0])


def src_row_to_canvas_69(src_y: int, outer_w: int, margin_top: int) -> float:
    scale = outer_w / BEZEL69_NATIVE[0]
    dev_y = BEZEL69_AT[1] + src_y * BEZEL69_SLOT[1] / CANVAS_69[1]
    return dev_y * scale + margin_top


def single_panel_top_69(src: Image.Image, bezel: Image.Image, locale: str,
                        lines_cfg: list[tuple[str, int, bool, int]],
                        force_top: int | None = None
                        ) -> tuple[Image.Image, dict]:
    base = Image.new("RGBA", CANVAS_69, ACCENT + (255,))
    h_h = headline_height_69(locale, lines_cfg)
    hy0 = HEADLINE_TOP_MARGIN_69
    hy1 = hy0 + h_h
    dev_h = aspect_h_69(DEVICE_W_69)
    x0 = (CANVAS_69[0] - DEVICE_W_69) // 2
    y0 = hy1 + MIN_GAP_69 if force_top is None else force_top
    if y0 - hy1 < MIN_GAP_69:
        raise BuilderError(
            f"headline/device overlap: shot top {y0} - headline bottom {hy1} "
            f"= {y0 - hy1} < {MIN_GAP_69}; caption does not fit the approved "
            "template — 9.2 finding, never silently shrunk")
    if y0 + dev_h > CANVAS_69[1]:
        raise BuilderError(
            f"single device overflow bottom: {y0 + dev_h} > {CANVAS_69[1]} "
            f"(headline block {h_h}px); caption does not fit the approved "
            "template — 9.2 finding, never silently shrunk")
    draw_headline_69(base, locale, lines_cfg, hy0)
    box = (x0, y0, x0 + DEVICE_W_69, y0 + dev_h)
    out = place_device_69(base, device_shot_69(src, bezel), box)
    return out, {"headline_anchor": "top",
                 "headline_box": [hy0, hy1],
                 "shot_box": list(box)}


def la_panel_v11_69(lock: Image.Image, compact: Image.Image,
                    expanded: Image.Image, bezel: Image.Image, locale: str,
                    lines_cfg: list[tuple[str, int, bool, int]]
                    ) -> tuple[Image.Image, dict]:
    """LA v11: owner Figma geometry verbatim; back compact behind front expanded."""
    base = Image.new("RGBA", CANVAS_69, ACCENT + (255,))

    top_box = tuple(TOP_BOX_FIGMA)
    back_box = tuple(BACK_BOX_FIGMA)
    front_box = tuple(FRONT_BOX_FIGMA)
    hy0, hy1 = HEADLINE_BOX_FIGMA

    if top_box[2] - top_box[0] != 1152:
        raise BuilderError("top width must be Figma 1152")
    if top_box[3] - top_box[1] != aspect_h_69(1152) != 2351:
        raise BuilderError("top aspect drift")
    if back_box[2] - back_box[0] != 992:
        raise BuilderError("back width must be Figma 992")
    if back_box[3] - back_box[1] != aspect_h_69(992) != 2024:
        raise BuilderError("back aspect drift")
    if front_box[2] - front_box[0] != 1152:
        raise BuilderError("front width must be Figma 1152")
    if front_box[3] - front_box[1] != aspect_h_69(1152) != 2351:
        raise BuilderError("front aspect drift")
    if hy1 - hy0 != 210:
        raise BuilderError("headline band must be Figma h210")

    if not top_box[1] < 0:
        raise BuilderError(f"top must bleed off-canvas, got {top_box[1]}")
    if not top_box[3] + MIN_GAP_69 <= hy0:
        raise BuilderError(
            f"top/headline overlap: device bottom {top_box[3]}, headline {hy0}")
    if not hy1 + MIN_GAP_69 <= back_box[1]:
        raise BuilderError(
            f"headline/back overlap: headline bottom {hy1}, back top {back_box[1]}")
    if not back_box[1] < front_box[1] < back_box[3]:
        raise BuilderError("stack must overlap vertically")
    if not (front_box[0] < back_box[2] and back_box[0] < front_box[2]):
        raise BuilderError("stack must overlap horizontally")
    if not front_box[3] > back_box[3]:
        raise BuilderError("front must extend below the back")

    banner_top = src_row_to_canvas_69(BANNER_SRC_TOP, 1152, top_box[1])
    banner_bot = src_row_to_canvas_69(BANNER_SRC_BOTTOM, 1152, top_box[1])
    if banner_top < 0:
        raise BuilderError(f"banner top cropped off-canvas: {banner_top}")
    if not banner_bot + MIN_GAP_69 <= hy0:
        raise BuilderError(
            f"banner not clear of headline: banner bottom {banner_bot}, headline {hy0}")

    text_top, text_bot = draw_headline_centered_69(base, locale, lines_cfg,
                                                   [hy0, hy1])
    out = place_device_69(base, device_shot_69(lock, bezel), top_box)
    out = place_device_69(out, device_shot_69(compact, bezel), back_box)
    out = place_device_69(out, device_shot_69(expanded, bezel), front_box)
    layout = {"headline_anchor": "center",
              "headline_box": [hy0, hy1],
              "headline_text_box": [text_top, text_bot],
              "device_top_box": list(top_box),
              "device_top_source_frame": "la-lock (full lock screen, banner included)",
              "device_top_outer_width_px": 1152,
              "device_top_bleed_px": -top_box[1],
              "banner_src_rows": [BANNER_SRC_TOP, BANNER_SRC_BOTTOM],
              "banner_canvas_rows": [round(banner_top), round(banner_bot)],
              "device_back_box": list(back_box),
              "device_back_source_frame": "la-compact (full home screen, compact island included)",
              "device_back_outer_width_px": 992,
              "device_back_bleed_px": back_box[3] - CANVAS_69[1],
              "device_front_box": list(front_box),
              "device_front_source_frame": "la-expanded (full home screen, expanded island included)",
              "device_front_outer_width_px": 1152,
              "device_front_bleed_px": front_box[3] - CANVAS_69[1]}
    return out, layout


def near_bg(px: tuple[int, ...]) -> bool:
    return all(abs(a - b) <= BG_TOL for a, b in zip(px[:3], ACCENT))


def panel_filename(key: str, locale: str, canvas: tuple[int, int]) -> str:
    return (f"panel-{PANEL_FILE_WORD[key]}-{locale}-"
            f"{canvas[0]}x{canvas[1]}.png")


def expected_for(locale: str, size: str) -> dict:
    if locale == "en" and size == "6.9":
        return dict(EXPECTED_EN69)
    if locale == "en" and size == "ipad13":
        return dict(EXPECTED_EN_IPAD)
    raise BuilderError(
        f"no approved template hashes for locale={locale} size={size}; "
        "--check-template covers owner-approved EN compositions only")


def build_69(locale: str, caps: dict, captions_version: str,
             frames_dir: Path, manifest_path: Path, bezel_path: Path,
             out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    src_hashes, run_meta = verify_sources(frames_dir, manifest_path,
                                          NEEDED_FRAMES_69, CANVAS_69)
    bezel_info = verify_bezel_69(bezel_path)
    bezel = load_bezel(bezel_path)
    copy = copy_for_69(caps)
    raw = {k: Image.open(frames_dir / f"{k}.png") for k in NEEDED_FRAMES_69}
    panels: dict = {}
    try:
        plan = [
            ("track", "track-running", copy["track"], None),
            ("insights", "insights", copy["insights"], None),
            ("history", "history", copy["history"], HISTORY_SHOT_TOP_69),
            ("add-entry", "add-entry", copy["add-entry"], ADD_ENTRY_SHOT_TOP_69),
        ]
        for key, frame, hl, top in plan:
            img, layout = single_panel_top_69(raw[frame], bezel, locale, hl,
                                              force_top=top)
            img = img.convert("RGB")
            if tuple(img.size) != CANVAS_69:
                raise BuilderError(f"output size drift {key}: {img.size}")
            name = panel_filename(key, locale, CANVAS_69)
            img.save(out_dir / name)
            panels[name] = {"panel": key, "source_frame": frame,
                            "sha256": sha(out_dir / name),
                            "geometry": list(CANVAS_69), **layout}

        la_img, la_layout = la_panel_v11_69(raw["la-lock"], raw["la-compact"],
                                            raw["la-expanded"], bezel, locale,
                                            copy["la"])
        la_img = la_img.convert("RGB")
        if tuple(la_img.size) != CANVAS_69:
            raise BuilderError(f"output size drift la: {la_img.size}")
        la_name = panel_filename("la", locale, CANVAS_69)
        la_img.save(out_dir / la_name)
        panels[la_name] = {"panel": "la",
                           "source_frames": ["la-lock", "la-compact", "la-expanded"],
                           "sha256": sha(out_dir / la_name),
                           "geometry": list(CANVAS_69), **la_layout}
    finally:
        for im in raw.values():
            im.close()

    headlines = {
        panel_filename("track", locale, CANVAS_69): [copy["track"][0][0]],
        panel_filename("insights", locale, CANVAS_69): [copy["insights"][0][0]],
        panel_filename("history", locale, CANVAS_69): [copy["history"][0][0],
                                                       copy["history"][1][0]],
        panel_filename("add-entry", locale, CANVAS_69): [copy["add-entry"][0][0]],
        panel_filename("la", locale, CANVAS_69): [copy["la"][0][0]],
    }
    recipe = {
        "schema_version": 1,
        "template_version": TEMPLATE_69,
        "template_mix": {
            "track": "v12 single (headline TOP y=168, shot top 444)",
            "insights": "v12 single (headline TOP y=168, shot top 444)",
            "history": "v12b single (headline TOP y=168 unchanged, shot top 444)",
            "add-entry": "v12 single geometry (headline TOP y=168, shot top 444)",
            "live-activities": "v11 owner-Figma geometry verbatim "
                               "(top lock bleed, center band, back/front stack)",
        },
        "approval_status": REVIEW_STATUS,
        "canvas": {"width": CANVAS_69[0], "height": CANVAS_69[1]},
        "background": "#0A84FF",
        "background_note": "Theme.accentPrimary field; singles carry white "
                           "headline TOP; LA carries white headline in the "
                           "Figma center band. Source pixels LANCZOS-scaled "
                           "only, aspect-exact; overflow canvas-clipped.",
        "bezel": {
            "asset": bezel_path.name,
            "sha256": bezel_info["sha256"],
            "native_px": bezel_info["size"],
            "profile": bezel_info.get("profile", LEGACY_BEZEL_PROFILE_69),
            "screen_slot_px": bezel_info.get("screen_slot_px",
                                             list(BEZEL69_SLOT)),
            "screen_at_px": bezel_info.get("screen_at_px", list(BEZEL69_AT)),
            "screen_mask_radius_px": bezel_info.get("screen_mask_radius_px",
                                                   BEZEL69_MASK_R),
        },
        "device_outer_width_px": DEVICE_W_69,
        "device_back_outer_width_px": DEVICE_BACK_W_69,
        "headline_top_margin_px": HEADLINE_TOP_MARGIN_69,
        "min_gap_px": MIN_GAP_69,
        "figma_geometry": {
            "device_top_box": TOP_BOX_FIGMA,
            "headline_box": HEADLINE_BOX_FIGMA,
            "device_back_box": BACK_BOX_FIGMA,
            "device_front_box": FRONT_BOX_FIGMA,
        },
        "history_shot_top_override_px": HISTORY_SHOT_TOP_69,
        "add_entry_shot_top_px": ADD_ENTRY_SHOT_TOP_69,
        "locale": locale,
        "captions_version": captions_version,
        "run_id": run_meta.get("run_id"),
        "deck_version": run_meta.get("deck_version"),
        "treatment": run_meta.get("treatment"),
        "headlines": headlines,
        "sources": {k: {"file": str(frames_dir / f"{k}.png"),
                        "screenshot_sha256": v}
                    for k, v in src_hashes.items()},
        "font": {"bold": f"{FONT_HEL}#1 Helvetica-Bold"
                 if locale != "zh-Hans" else f"{FONT_HIRA}#1 HiraginoSansGB-W6",
                 "regular": f"{FONT_HEL}#0 Helvetica"
                 if locale != "zh-Hans" else f"{FONT_HIRA}#0 HiraginoSansGB-W3"},
        "panels": panels,
        "renderer": {"tool": "Pillow",
                     "pillow_version": _PIL.__version__ if _PIL else "unknown",
                     "python_version": platform.python_version(),
                     "resample": "LANCZOS", "host": platform.platform()},
    }
    recipe_name = f"panels-{locale}-{CANVAS_69[0]}x{CANVAS_69[1]}.recipe.json"
    (out_dir / recipe_name).write_text(
        json.dumps(recipe, indent=2, sort_keys=True) + "\n")
    recipe["_recipe_file"] = recipe_name
    return recipe


# ---------------------------------------------------------------------------
# 6.3 rendering (v13 composition scaled per-axis; bezel measured, not pinned)
# ---------------------------------------------------------------------------

def aspect_h_63(outer_w: int, bezel_size: tuple[int, int]) -> int:
    return round(outer_w * bezel_size[1] / bezel_size[0])


def mask_r_63(slot: tuple[int, int]) -> int:
    return int(round(BEZEL69_MASK_R * slot[0] / BEZEL69_SLOT[0]))


def device_shot_63(src: Image.Image, bezel: Image.Image,
                   slot: tuple[int, int], at: tuple[int, int],
                   bezel_size: tuple[int, int],
                   mask_r: int | None = None) -> Image.Image:
    """Composite one 1206x2622 capture into the 6.3 device art.

    Apple profile (slot == canvas): 1:1 native paste, never resampled.
    Legacy structural profile: LANCZOS-scaled to the measured slot (frozen
    behavior). mask_r defaults to the legacy slot-derived radius; pass the
    verifier's pinned radius for Apple art.
    """
    if tuple(src.size) != CANVAS_63:
        raise BuilderError(
            f"cross-size art rejected: {src.size} vs canvas {CANVAS_63}")
    if mask_r is None:
        mask_r = mask_r_63(slot)
    if tuple(src.size) == tuple(slot):
        shot = src.convert("RGBA")
    else:
        shot = src.resize(slot, Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", slot, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, *slot], radius=mask_r, fill=255)
    shot.putalpha(mask)
    dev = Image.new("RGBA", bezel_size, (0, 0, 0, 0))
    dev.paste(shot, at, shot)
    dev.alpha_composite(bezel)
    return dev


def place_device_63(base: Image.Image, dev: Image.Image,
                    box: tuple[int, int, int, int]) -> Image.Image:
    card = Image.new("RGBA", CANVAS_63, (0, 0, 0, 0))
    sh = Image.new("RGBA", CANVAS_63, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.rounded_rectangle(box, radius=_qx(150), fill=(0, 0, 0, 90))
    card.alpha_composite(sh.filter(ImageFilter.GaussianBlur(_qy(38))))
    fitted = dev.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    card.alpha_composite(fitted, (box[0], box[1]))
    return Image.alpha_composite(base, card)


def src_row_to_canvas_63(src_y: int, outer_w: int, margin_top: int,
                         slot: tuple[int, int], at: tuple[int, int],
                         bezel_size: tuple[int, int]) -> float:
    scale = outer_w / bezel_size[0]
    dev_y = at[1] + src_y * slot[1] / CANVAS_63[1]
    return dev_y * scale + margin_top


def single_panel_top_63(src: Image.Image, bezel: Image.Image,
                        slot: tuple[int, int], at: tuple[int, int],
                        bezel_size: tuple[int, int], locale: str,
                        lines_cfg: list[tuple[str, int, bool, int]],
                        force_top: int | None = None,
                        mask_r: int | None = None
                        ) -> tuple[Image.Image, dict]:
    base = Image.new("RGBA", CANVAS_63, ACCENT + (255,))
    h_h = headline_height_63(locale, lines_cfg)
    hy0 = HEADLINE_TOP_MARGIN_63
    hy1 = hy0 + h_h
    dev_h = aspect_h_63(DEVICE_W_63, bezel_size)
    x0 = (CANVAS_63[0] - DEVICE_W_63) // 2
    y0 = hy1 + MIN_GAP_63 if force_top is None else force_top
    if y0 - hy1 < MIN_GAP_63:
        raise BuilderError(
            f"headline/device overlap: shot top {y0} - headline bottom {hy1} "
            f"= {y0 - hy1} < {MIN_GAP_63}; caption does not fit the scaled "
            "template — 9.2 finding, never silently shrunk")
    if y0 + dev_h > CANVAS_63[1]:
        raise BuilderError(
            f"single device overflow bottom: {y0 + dev_h} > {CANVAS_63[1]} "
            f"(headline block {h_h}px); caption does not fit the scaled "
            "template — 9.2 finding, never silently shrunk")
    draw_headline_63(base, locale, lines_cfg, hy0)
    box = (x0, y0, x0 + DEVICE_W_63, y0 + dev_h)
    out = place_device_63(base, device_shot_63(src, bezel, slot, at,
                                              bezel_size, mask_r), box)
    return out, {"headline_anchor": "top",
                 "headline_box": [hy0, hy1],
                 "shot_box": list(box)}


def la_panel_v11_63(lock: Image.Image, compact: Image.Image,
                    expanded: Image.Image, bezel: Image.Image,
                    slot: tuple[int, int], at: tuple[int, int],
                    bezel_size: tuple[int, int], locale: str,
                    lines_cfg: list[tuple[str, int, bool, int]],
                    mask_r: int | None = None
                    ) -> tuple[Image.Image, dict]:
    """LA scaled-v11: same stacking as v13 (top lock bleed, center band,
    back compact behind front expanded) with per-axis scaled boxes; box
    heights follow the measured bezel aspect."""
    base = Image.new("RGBA", CANVAS_63, ACCENT + (255,))

    top_box = (TOP_BOX_63[0], TOP_BOX_63[1],
               TOP_BOX_63[0] + DEVICE_W_63,
               TOP_BOX_63[1] + aspect_h_63(DEVICE_W_63, bezel_size))
    back_box = (BACK_BOX_63[0], BACK_BOX_63[1],
                BACK_BOX_63[0] + DEVICE_BACK_W_63,
                BACK_BOX_63[1] + aspect_h_63(DEVICE_BACK_W_63, bezel_size))
    front_box = (FRONT_BOX_63[0], FRONT_BOX_63[1],
                 FRONT_BOX_63[0] + DEVICE_W_63,
                 FRONT_BOX_63[1] + aspect_h_63(DEVICE_W_63, bezel_size))
    hy0, hy1 = HEADLINE_BOX_63

    if not top_box[1] < 0:
        raise BuilderError(f"top must bleed off-canvas, got {top_box[1]}")
    if not top_box[3] + MIN_GAP_63 <= hy0:
        raise BuilderError(
            f"top/headline overlap: device bottom {top_box[3]}, headline {hy0}")
    if not hy1 + MIN_GAP_63 <= back_box[1]:
        raise BuilderError(
            f"headline/back overlap: headline bottom {hy1}, back top {back_box[1]}")
    if not back_box[1] < front_box[1] < back_box[3]:
        raise BuilderError("stack must overlap vertically")
    if not (front_box[0] < back_box[2] and back_box[0] < front_box[2]):
        raise BuilderError("stack must overlap horizontally")
    if not front_box[3] > back_box[3]:
        raise BuilderError("front must extend below the back")

    banner_top = src_row_to_canvas_63(BANNER_SRC_TOP_63, DEVICE_W_63,
                                      top_box[1], slot, at, bezel_size)
    banner_bot = src_row_to_canvas_63(BANNER_SRC_BOTTOM_63, DEVICE_W_63,
                                      top_box[1], slot, at, bezel_size)
    if banner_top < 0:
        raise BuilderError(f"banner top cropped off-canvas: {banner_top}")
    if not banner_bot + MIN_GAP_63 <= hy0:
        raise BuilderError(
            f"banner not clear of headline: banner bottom {banner_bot}, headline {hy0}")

    text_top, text_bot = draw_headline_centered_63(base, locale, lines_cfg,
                                                   [hy0, hy1])
    out = place_device_63(base, device_shot_63(lock, bezel, slot, at,
                                              bezel_size, mask_r), top_box)
    out = place_device_63(out, device_shot_63(compact, bezel, slot, at,
                                             bezel_size, mask_r), back_box)
    out = place_device_63(out, device_shot_63(expanded, bezel, slot, at,
                                             bezel_size, mask_r), front_box)
    layout = {"headline_anchor": "center",
              "headline_box": [hy0, hy1],
              "headline_text_box": [text_top, text_bot],
              "device_top_box": list(top_box),
              "device_top_source_frame": "la-lock (full lock screen, banner included)",
              "device_top_outer_width_px": DEVICE_W_63,
              "device_top_bleed_px": -top_box[1],
              "banner_src_rows": [BANNER_SRC_TOP_63, BANNER_SRC_BOTTOM_63],
              "banner_canvas_rows": [round(banner_top), round(banner_bot)],
              "device_back_box": list(back_box),
              "device_back_source_frame": "la-compact (full home screen, compact island included)",
              "device_back_outer_width_px": DEVICE_BACK_W_63,
              "device_back_bleed_px": back_box[3] - CANVAS_63[1],
              "device_front_box": list(front_box),
              "device_front_source_frame": "la-expanded (full home screen, expanded island included)",
              "device_front_outer_width_px": DEVICE_W_63,
              "device_front_bleed_px": front_box[3] - CANVAS_63[1]}
    return out, layout


def build_63(locale: str, caps: dict, captions_version: str,
             frames_dir: Path, manifest_path: Path, bezel_path: Path,
             out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    src_hashes, run_meta = verify_sources(frames_dir, manifest_path,
                                          NEEDED_FRAMES_69, CANVAS_63)
    bezel_info = verify_bezel_63(bezel_path)
    bezel = load_bezel(bezel_path)
    bezel_size = tuple(bezel.size)
    slot = tuple(bezel_info["screen_slot_px"])  # type: ignore[assignment]
    at = tuple(bezel_info["screen_at_px"])  # type: ignore[assignment]
    mask_r = int(bezel_info["screen_mask_radius_px"])
    copy = copy_for_63(caps)
    raw = {k: Image.open(frames_dir / f"{k}.png") for k in NEEDED_FRAMES_69}
    panels: dict = {}
    try:
        plan = [
            ("track", "track-running", copy["track"], None),
            ("insights", "insights", copy["insights"], None),
            ("history", "history", copy["history"], HISTORY_SHOT_TOP_63),
            ("add-entry", "add-entry", copy["add-entry"], ADD_ENTRY_SHOT_TOP_63),
        ]
        for key, frame, hl, top in plan:
            img, layout = single_panel_top_63(raw[frame], bezel, slot, at,
                                              bezel_size, locale, hl,
                                              force_top=top, mask_r=mask_r)
            img = img.convert("RGB")
            if tuple(img.size) != CANVAS_63:
                raise BuilderError(f"output size drift {key}: {img.size}")
            name = panel_filename(key, locale, CANVAS_63)
            img.save(out_dir / name)
            panels[name] = {"panel": key, "source_frame": frame,
                            "sha256": sha(out_dir / name),
                            "geometry": list(CANVAS_63), **layout}

        la_img, la_layout = la_panel_v11_63(raw["la-lock"], raw["la-compact"],
                                            raw["la-expanded"], bezel, slot,
                                            at, bezel_size, locale, copy["la"],
                                            mask_r=mask_r)
        la_img = la_img.convert("RGB")
        if tuple(la_img.size) != CANVAS_63:
            raise BuilderError(f"output size drift la: {la_img.size}")
        la_name = panel_filename("la", locale, CANVAS_63)
        la_img.save(out_dir / la_name)
        panels[la_name] = {"panel": "la",
                           "source_frames": ["la-lock", "la-compact", "la-expanded"],
                           "sha256": sha(out_dir / la_name),
                           "geometry": list(CANVAS_63), **la_layout}
    finally:
        for im in raw.values():
            im.close()

    headlines = {
        panel_filename("track", locale, CANVAS_63): [copy["track"][0][0]],
        panel_filename("insights", locale, CANVAS_63): [copy["insights"][0][0]],
        panel_filename("history", locale, CANVAS_63): [copy["history"][0][0],
                                                       copy["history"][1][0]],
        panel_filename("add-entry", locale, CANVAS_63): [copy["add-entry"][0][0]],
        panel_filename("la", locale, CANVAS_63): [copy["la"][0][0]],
    }
    recipe = {
        "schema_version": 1,
        "template_version": TEMPLATE_69,
        "template_variant": "v13-scaled-63",
        "canvas_scale": {"from": "v13-6.9", "x": SX63, "y": SY63},
        "template_mix": {
            "track": "v13 single scaled (headline TOP, shot top scaled)",
            "insights": "v13 single scaled (headline TOP, shot top scaled)",
            "history": "v13 single scaled (headline TOP unchanged, shot top scaled)",
            "add-entry": "v13 single scaled (headline TOP, shot top scaled)",
            "live-activities": "v11 stacking scaled per-axis "
                               "(top lock bleed, center band, back/front stack; "
                               "box heights follow the measured bezel aspect)",
        },
        "approval_status": REVIEW_STATUS,
        "canvas": {"width": CANVAS_63[0], "height": CANVAS_63[1]},
        "background": "#0A84FF",
        "background_note": "Theme.accentPrimary field; singles carry white "
                           "headline TOP; LA carries white headline in the "
                           "scaled center band. Source pixels LANCZOS-scaled "
                           "only, aspect-exact; overflow canvas-clipped.",
        "bezel": {
            "asset": bezel_path.name,
            "sha256": bezel_info["sha256"],
            "native_px": bezel_info["size"],
            "profile": bezel_info.get("profile", "structural-legacy"),
            "screen_slot_px": bezel_info["screen_slot_px"],
            "screen_at_px": bezel_info["screen_at_px"],
            "screen_mask_radius_px": mask_r,
            "slot_aspect_deviation": bezel_info["slot_aspect_deviation"],
            "slot_clear_fraction": bezel_info["slot_clear_fraction"],
            "source": ("apple-bezels release asset "
                       + APPLE_SOURCE_63["name"]
                       + " (exact-profile verification; staged by "
                       "stage_bezel_assets.py)"
                       if bezel_info.get("profile")
                       == APPLE_SOURCE_63["profile"] else
                       "legacy structural bezel (thresholds frozen); "
                       "node binding was recorded at fetch time, not in "
                       "pixels"),
        },
        "device_outer_width_px": DEVICE_W_63,
        "device_back_outer_width_px": DEVICE_BACK_W_63,
        "headline_top_margin_px": HEADLINE_TOP_MARGIN_63,
        "min_gap_px": MIN_GAP_63,
        "scaled_geometry": {
            "device_top_origin": TOP_BOX_63[:3],
            "headline_box": HEADLINE_BOX_63,
            "device_back_origin": BACK_BOX_63[:3],
            "device_front_origin": FRONT_BOX_63[:3],
        },
        "history_shot_top_override_px": HISTORY_SHOT_TOP_63,
        "add_entry_shot_top_px": ADD_ENTRY_SHOT_TOP_63,
        "locale": locale,
        "captions_version": captions_version,
        "run_id": run_meta.get("run_id"),
        "deck_version": run_meta.get("deck_version"),
        "treatment": run_meta.get("treatment"),
        "headlines": headlines,
        "sources": {k: {"file": str(frames_dir / f"{k}.png"),
                        "screenshot_sha256": v}
                    for k, v in src_hashes.items()},
        "font": {"bold": f"{FONT_HEL}#1 Helvetica-Bold"
                 if locale != "zh-Hans" else f"{FONT_HIRA}#1 HiraginoSansGB-W6",
                 "regular": f"{FONT_HEL}#0 Helvetica"
                 if locale != "zh-Hans" else f"{FONT_HIRA}#0 HiraginoSansGB-W3"},
        "panels": panels,
        "renderer": {"tool": "Pillow",
                     "pillow_version": _PIL.__version__ if _PIL else "unknown",
                     "python_version": platform.python_version(),
                     "resample": "LANCZOS", "host": platform.platform()},
    }
    recipe_name = f"panels-{locale}-{CANVAS_63[0]}x{CANVAS_63[1]}.recipe.json"
    (out_dir / recipe_name).write_text(
        json.dumps(recipe, indent=2, sort_keys=True) + "\n")
    recipe["_recipe_file"] = recipe_name
    return recipe


# ---------------------------------------------------------------------------
# iPad rendering (verbatim ipad-v1 geometry)
# ---------------------------------------------------------------------------

def device_sheet_ipad(raw: Image.Image, bezel: Image.Image) -> Image.Image:
    if tuple(raw.size) != CAVITY_SIZE:
        raise BuilderError(
            f"cross-size art rejected: {raw.size} vs cavity {CAVITY_SIZE}")
    shot = raw.convert("RGBA")
    mask = Image.new("L", CAVITY_SIZE, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, CAVITY_SIZE[0], CAVITY_SIZE[1]], radius=CAVITY_R, fill=255)
    shot.putalpha(mask)
    dev = Image.new("RGBA", BEZEL_IPAD_NATIVE, (0, 0, 0, 0))
    dev.paste(shot, CAVITY_AT, shot)
    dev.alpha_composite(bezel)
    return dev


def solve_layout_ipad_for_locale(locale: str, copy: dict) -> tuple[int, int]:
    """Uniform (outer_w, shot_top) for all 4 panels.

    Solved with the build locale so localized (taller) headlines shrink
    the device honestly instead of overlapping it.
    """
    tallest = max(headline_height_ipad(locale, cfg) for cfg in copy.values())
    shot_top = HEADLINE_TOP_MARGIN_IPAD + tallest + MIN_GAP_IPAD
    outer_w = min(
        CANVAS_IPAD[0] - 2 * SIDE_MIN_IPAD,
        (CANVAS_IPAD[1] - BOTTOM_MIN_IPAD - shot_top) * BEZEL_IPAD_NATIVE[0]
        // BEZEL_IPAD_NATIVE[1],
    )
    if outer_w <= 0:
        raise BuilderError(
            f"no room for device: tallest headline {tallest}px leaves "
            f"shot_top {shot_top}; caption does not fit the approved "
            "template — 9.2 finding, never silently shrunk")
    dev_h = round(outer_w * BEZEL_IPAD_NATIVE[1] / BEZEL_IPAD_NATIVE[0])
    if not shot_top + dev_h + BOTTOM_MIN_IPAD <= CANVAS_IPAD[1]:
        raise BuilderError(
            f"device overflow bottom: shot_top {shot_top} + dev_h {dev_h} + "
            f"margin {BOTTOM_MIN_IPAD} > {CANVAS_IPAD[1]}; caption does not "
            "fit the approved template — 9.2 finding")
    if not (CANVAS_IPAD[0] - outer_w) // 2 >= SIDE_MIN_IPAD:
        raise BuilderError("device too wide for side margins")
    return outer_w, shot_top


def render_panel_ipad(raw: Image.Image, bezel: Image.Image, locale: str,
                      lines_cfg: list,
                      outer_w: int, shot_top: int) -> tuple[Image.Image, dict]:
    base = Image.new("RGBA", CANVAS_IPAD, ACCENT + (255,))
    hy0, hy1 = draw_headline_ipad(base, locale, lines_cfg,
                                  HEADLINE_TOP_MARGIN_IPAD)
    dev_h = round(outer_w * BEZEL_IPAD_NATIVE[1] / BEZEL_IPAD_NATIVE[0])
    x0 = (CANVAS_IPAD[0] - outer_w) // 2
    box = (x0, shot_top, x0 + outer_w, shot_top + dev_h)
    if not shot_top - hy1 >= MIN_GAP_IPAD:
        raise BuilderError("headline/device gap violated")
    card = Image.new("RGBA", CANVAS_IPAD, (0, 0, 0, 0))
    sh = Image.new("RGBA", CANVAS_IPAD, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(box, radius=SHADOW_R_IPAD,
                                         fill=(0, 0, 0, 90))
    card.alpha_composite(sh.filter(ImageFilter.GaussianBlur(SHADOW_BLUR_IPAD)))
    fitted = device_sheet_ipad(raw, bezel).resize(
        (box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    card.alpha_composite(fitted, (box[0], box[1]))
    out = Image.alpha_composite(base, card).convert("RGB")
    return out, {"headline_anchor": "top", "headline_box": [hy0, hy1],
                 "device_box": list(box)}


def build_ipad(locale: str, caps: dict, captions_version: str,
               frames_dir: Path, manifest_path: Path, bezel_path: Path,
               out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    needed = tuple(PANEL_FRAMES_IPAD.values())
    # Evidence covers the rendered app frames plus the required Lock
    # Screen (Island stays N/A via probe, never filed).
    src_hashes, run_meta = verify_sources(frames_dir, manifest_path,
                                          needed, CANVAS_IPAD,
                                          evidence_frames=(*needed,
                                                            "la-lock"))
    bezel_info = verify_bezel_ipad(bezel_path)
    bezel = load_bezel(bezel_path)
    copy = copy_for_ipad(caps)
    outer_w, shot_top = solve_layout_ipad_for_locale(locale, copy)
    panels: dict = {}
    for key, frame in PANEL_FRAMES_IPAD.items():
        with Image.open(frames_dir / f"{frame}.png") as raw:
            img, geo = render_panel_ipad(raw, bezel, locale, copy[key],
                                         outer_w, shot_top)
        if tuple(img.size) != CANVAS_IPAD:
            raise BuilderError(f"output size drift {key}: {img.size}")
        name = panel_filename(key, locale, CANVAS_IPAD)
        img.save(out_dir / name)
        panels[name] = {"panel": key, "source_frame": frame,
                        "sha256": sha(out_dir / name),
                        "geometry": list(CANVAS_IPAD), **geo}
    headlines = {
        panel_filename("track", locale, CANVAS_IPAD): [copy["track"][0][0]],
        panel_filename("insights", locale, CANVAS_IPAD): [copy["insights"][0][0]],
        panel_filename("history", locale, CANVAS_IPAD): [copy["history"][0][0],
                                                         copy["history"][1][0]],
        panel_filename("add-entry", locale, CANVAS_IPAD): [copy["add-entry"][0][0]],
    }
    recipe = {
        "schema_version": 1,
        "template_version": TEMPLATE_IPAD,
        "approval_status": REVIEW_STATUS,
        "canvas": {"width": CANVAS_IPAD[0], "height": CANVAS_IPAD[1]},
        "background": "#0A84FF",
        "background_note": "Theme.accentPrimary field, same as approved iPhone "
                           "v13 template; white headline TOP on all 4 panels. "
                           "Raw frames pasted at NATIVE size into the measured "
                           "bezel cavity (zero resampling, aspect-exact); the "
                           "composited device sheet is LANCZOS-scaled once to "
                           "the solved outer width; full device stays on-canvas.",
        "bezel": {
            "asset": bezel_path.name,
            "sha256": bezel_info["sha256"],
            "native_px": bezel_info["size"],
            "cavity_at_px": list(CAVITY_AT),
            "cavity_size_px": list(CAVITY_SIZE),
            "mask_radius_px": CAVITY_R,
        },
        "device_layout": {"outer_width_px": outer_w, "shot_top_px": shot_top},
        "headline_top_margin_px": HEADLINE_TOP_MARGIN_IPAD,
        "min_gap_px": MIN_GAP_IPAD,
        "locale": locale,
        "captions_version": captions_version,
        "run_id": run_meta.get("run_id"),
        "deck_version": run_meta.get("deck_version"),
        "treatment": run_meta.get("treatment"),
        "headlines": headlines,
        "sources": {k: {"file": str(frames_dir / f"{k}.png"),
                        "screenshot_sha256": v}
                    for k, v in src_hashes.items()},
        "font": {"bold": f"{FONT_HEL}#1 Helvetica-Bold"
                 if locale != "zh-Hans" else f"{FONT_HIRA}#1 HiraginoSansGB-W6",
                 "regular": f"{FONT_HEL}#0 Helvetica"
                 if locale != "zh-Hans" else f"{FONT_HIRA}#0 HiraginoSansGB-W3"},
        "panels": panels,
        "renderer": {"tool": "Pillow",
                     "pillow_version": _PIL.__version__ if _PIL else "unknown",
                     "python_version": platform.python_version(),
                     "resample": "LANCZOS (device sheet only; raw-to-cavity "
                                 "is a native 1:1 paste)",
                     "host": platform.platform()},
    }
    recipe_name = f"panels-{locale}-{CANVAS_IPAD[0]}x{CANVAS_IPAD[1]}.recipe.json"
    (out_dir / recipe_name).write_text(
        json.dumps(recipe, indent=2, sort_keys=True) + "\n")
    recipe["_recipe_file"] = recipe_name
    return recipe


# ---------------------------------------------------------------------------
# Structural selftests (geometry + pixel probes on built outputs)
# ---------------------------------------------------------------------------

def selftest_69(out_dir: Path, recipe: dict) -> list[str]:
    """Structural checks mirroring build_final_v13.selftest (no draft refs)."""
    lines: list[str] = []
    if recipe["template_version"] != TEMPLATE_69:
        raise BuilderError("selftest: template_version drift")
    if recipe["canvas"] != {"width": CANVAS_69[0], "height": CANVAS_69[1]}:
        raise BuilderError("selftest: canvas drift")
    if recipe["background"] != "#0A84FF":
        raise BuilderError("selftest: background drift")
    for name, p in recipe["panels"].items():
        with Image.open(out_dir / name) as img:
            size = tuple(img.size)
        if size != CANVAS_69:
            raise BuilderError(f"selftest: {name} size drift {size}")
        if sha(out_dir / name) != p["sha256"]:
            raise BuilderError(f"selftest: {name} hash drift vs recipe")
    for key in ("track", "insights", "history", "add-entry"):
        name = panel_filename(key, recipe["locale"], CANVAS_69)
        p = recipe["panels"][name]
        box = p["shot_box"]
        if p["headline_anchor"] != "top":
            raise BuilderError(f"selftest: {name} headline must be TOP")
        if p["headline_box"][0] != HEADLINE_TOP_MARGIN_69:
            raise BuilderError(f"selftest: {name} headline top drift")
        if box[2] - box[0] != DEVICE_W_69 != 1152:
            raise BuilderError(f"selftest: {name} width drift {box}")
        if box[3] - box[1] != aspect_h_69(DEVICE_W_69) != 2351:
            raise BuilderError(f"selftest: {name} aspect drift {box}")
        if not box[1] - p["headline_box"][1] >= MIN_GAP_69:
            raise BuilderError(f"selftest: {name} headline/device gap")
        if not box[3] <= CANVAS_69[1]:
            raise BuilderError(f"selftest: {name} overflow")
        with Image.open(out_dir / name) as im:
            rgb = im.convert("RGB")
        hy0, hy1 = p["headline_box"]
        rows = [hy0 + 25, hy0 + 75, hy0 + (hy1 - hy0) - 25]
        if not any(all(c > 200 for c in rgb.getpixel((xx, yy)))
                   for yy in rows for xx in range(300, 1021, 20)):
            raise BuilderError(f"selftest: {name} headline must show white text")
        if not near_bg(rgb.getpixel((10, 0))):
            raise BuilderError(f"selftest: {name} top corner must stay bg")
        if near_bg(rgb.getpixel((660, (box[1] + box[3]) // 2))):
            raise BuilderError(f"selftest: {name} device mid must show device")
        lines.append(f"OK {name} {p['sha256'][:12]} "
                     f"headline={p['headline_box']} shot={box}")

    la_name = panel_filename("la", recipe["locale"], CANVAS_69)
    p = recipe["panels"][la_name]
    if p["source_frames"] != ["la-lock", "la-compact", "la-expanded"]:
        raise BuilderError("selftest: LA source frames drift")
    if p["headline_anchor"] != "center":
        raise BuilderError("selftest: LA headline must be centered")
    if p["device_top_box"] != TOP_BOX_FIGMA:
        raise BuilderError(f"selftest: top drift {p['device_top_box']}")
    if p["headline_box"] != HEADLINE_BOX_FIGMA:
        raise BuilderError(f"selftest: headline drift {p['headline_box']}")
    if p["device_back_box"] != BACK_BOX_FIGMA:
        raise BuilderError(f"selftest: back drift {p['device_back_box']}")
    if p["device_front_box"] != FRONT_BOX_FIGMA:
        raise BuilderError(f"selftest: front drift {p['device_front_box']}")
    if p["device_top_bleed_px"] != 1176:
        raise BuilderError("selftest: top bleed drift")
    if p["device_front_bleed_px"] != FRONT_BOX_FIGMA[3] - CANVAS_69[1] != 1225:
        raise BuilderError("selftest: front bleed drift")
    if p["device_back_bleed_px"] != BACK_BOX_FIGMA[3] - CANVAS_69[1] != 743:
        raise BuilderError("selftest: back bleed drift")
    tt, tb = p["headline_text_box"]
    hy0, hy1 = p["headline_box"]
    if not (hy0 <= tt and tb <= hy1):
        raise BuilderError("selftest: headline text escapes Figma band")
    if abs((tt - hy0) - (hy1 - tb)) > 1:
        raise BuilderError("selftest: headline text not centered")
    with Image.open(out_dir / la_name) as im:
        rgb = im.convert("RGB")
    if near_bg(rgb.getpixel((660, 0))):
        raise BuilderError("selftest: top row must show bled device")
    if not near_bg(rgb.getpixel((10, 0))):
        raise BuilderError("selftest: top row outside device must stay bg")
    exp_top, exp_bot = p["banner_canvas_rows"]
    if not 0 <= exp_top < exp_bot < hy0:
        raise BuilderError("selftest: banner must sit on-canvas above headline")
    for yy in (exp_top + 10, (exp_top + exp_bot) // 2, exp_bot - 10):
        if near_bg(rgb.getpixel((660, yy))):
            raise BuilderError(f"selftest: banner row {yy} must show device")
    rows = [tt + 25, tt + 75, tt + 125, tt + (tb - tt) - 25]
    if not any(all(c > 200 for c in rgb.getpixel((xx, yy)))
               for yy in rows for xx in range(300, 1021, 20)):
        raise BuilderError("selftest: LA headline must show white text")
    if near_bg(rgb.getpixel((660, CANVAS_69[1] - 1))):
        raise BuilderError("selftest: bottom row must show bled front")
    if not near_bg(rgb.getpixel((1310, CANVAS_69[1] - 1))):
        raise BuilderError("selftest: bottom corner must stay bg")
    if near_bg(rgb.getpixel((660, 1600))):
        raise BuilderError("selftest: back strip must show device")
    if near_bg(rgb.getpixel((100, 2000))):
        raise BuilderError("selftest: front side strip must show device")
    if not near_bg(rgb.getpixel((10, 1200))):
        raise BuilderError("selftest: top-headline gap must stay bg")
    if not near_bg(rgb.getpixel((10, 1550))):
        raise BuilderError("selftest: headline-back gap must stay bg")
    lines.append(f"OK {la_name} {p['sha256'][:12]} top={p['device_top_box']} "
                 f"headline={p['headline_box']} back={p['device_back_box']} "
                 f"front={p['device_front_box']} banner={p['banner_canvas_rows']}")
    return lines


def selftest_63(out_dir: Path, recipe: dict) -> list[str]:
    """Structural checks for the scaled 6.3 composition.

    Mirrors selftest_69, but box heights follow the measured bezel aspect
    recorded in the recipe (native_px) instead of pinned Figma values, and
    all probe coordinates derive from the recorded boxes.
    """
    lines: list[str] = []
    if recipe["template_version"] != TEMPLATE_69:
        raise BuilderError("selftest: template_version drift")
    if recipe.get("template_variant") != "v13-scaled-63":
        raise BuilderError("selftest: template_variant drift")
    if recipe["canvas"] != {"width": CANVAS_63[0], "height": CANVAS_63[1]}:
        raise BuilderError("selftest: canvas drift")
    if recipe["background"] != "#0A84FF":
        raise BuilderError("selftest: background drift")
    bezel_native = recipe.get("bezel", {}).get("native_px")
    if (not isinstance(bezel_native, list) or len(bezel_native) != 2
            or not all(isinstance(v, int) and v > 0 for v in bezel_native)):
        raise BuilderError("selftest: bezel native_px missing")
    bn_w, bn_h = bezel_native
    cx = CANVAS_63[0] // 2
    scan_xs = list(range(_qx(300), _qx(1021), 20))

    def expect_aspect(name: str, box: list[int], outer_w: int) -> None:
        want_h = round(outer_w * bn_h / bn_w)
        if abs((box[3] - box[1]) - want_h) > 1:
            raise BuilderError(
                f"selftest: {name} aspect drift {box} vs bezel {bezel_native}")

    for name, p in recipe["panels"].items():
        with Image.open(out_dir / name) as img:
            size = tuple(img.size)
        if size != CANVAS_63:
            raise BuilderError(f"selftest: {name} size drift {size}")
        if sha(out_dir / name) != p["sha256"]:
            raise BuilderError(f"selftest: {name} hash drift vs recipe")
    for key in ("track", "insights", "history", "add-entry"):
        name = panel_filename(key, recipe["locale"], CANVAS_63)
        p = recipe["panels"][name]
        box = p["shot_box"]
        if p["headline_anchor"] != "top":
            raise BuilderError(f"selftest: {name} headline must be TOP")
        if p["headline_box"][0] != HEADLINE_TOP_MARGIN_63:
            raise BuilderError(f"selftest: {name} headline top drift")
        if box[2] - box[0] != DEVICE_W_63:
            raise BuilderError(f"selftest: {name} width drift {box}")
        expect_aspect(name, box, DEVICE_W_63)
        if not box[1] - p["headline_box"][1] >= MIN_GAP_63:
            raise BuilderError(f"selftest: {name} headline/device gap")
        if not box[3] <= CANVAS_63[1]:
            raise BuilderError(f"selftest: {name} overflow")
        with Image.open(out_dir / name) as im:
            rgb = im.convert("RGB")
        hy0, hy1 = p["headline_box"]
        rows = [hy0 + _qy(25), hy0 + _qy(75), hy1 - _qy(25)]
        if not any(all(c > 200 for c in rgb.getpixel((xx, yy)))
                   for yy in rows for xx in scan_xs):
            raise BuilderError(f"selftest: {name} headline must show white text")
        if not near_bg(rgb.getpixel((10, 0))):
            raise BuilderError(f"selftest: {name} top corner must stay bg")
        if near_bg(rgb.getpixel((cx, (box[1] + box[3]) // 2))):
            raise BuilderError(f"selftest: {name} device mid must show device")
        lines.append(f"OK {name} {p['sha256'][:12]} "
                     f"headline={p['headline_box']} shot={box}")

    la_name = panel_filename("la", recipe["locale"], CANVAS_63)
    p = recipe["panels"][la_name]
    if p["source_frames"] != ["la-lock", "la-compact", "la-expanded"]:
        raise BuilderError("selftest: LA source frames drift")
    if p["headline_anchor"] != "center":
        raise BuilderError("selftest: LA headline must be centered")
    if p["headline_box"] != HEADLINE_BOX_63:
        raise BuilderError(f"selftest: headline drift {p['headline_box']}")
    top_box, back_box, front_box = (p["device_top_box"], p["device_back_box"],
                                    p["device_front_box"])
    if top_box[0] != TOP_BOX_63[0] or top_box[2] - top_box[0] != DEVICE_W_63:
        raise BuilderError(f"selftest: top drift {top_box}")
    if back_box[0] != BACK_BOX_63[0] or back_box[2] - back_box[0] != DEVICE_BACK_W_63:
        raise BuilderError(f"selftest: back drift {back_box}")
    if front_box[0] != FRONT_BOX_63[0] or front_box[2] - front_box[0] != DEVICE_W_63:
        raise BuilderError(f"selftest: front drift {front_box}")
    expect_aspect(la_name + " top", top_box, DEVICE_W_63)
    expect_aspect(la_name + " back", back_box, DEVICE_BACK_W_63)
    expect_aspect(la_name + " front", front_box, DEVICE_W_63)
    if p["device_top_bleed_px"] != -top_box[1] or p["device_top_bleed_px"] <= 0:
        raise BuilderError("selftest: top bleed drift")
    if (p["device_front_bleed_px"] != front_box[3] - CANVAS_63[1]
            or p["device_front_bleed_px"] <= 0):
        raise BuilderError("selftest: front bleed drift")
    if (p["device_back_bleed_px"] != back_box[3] - CANVAS_63[1]
            or p["device_back_bleed_px"] <= 0):
        raise BuilderError("selftest: back bleed drift")
    if not top_box[3] + MIN_GAP_63 <= p["headline_box"][0]:
        raise BuilderError("selftest: top/headline overlap")
    if not p["headline_box"][1] + MIN_GAP_63 <= back_box[1]:
        raise BuilderError("selftest: headline/back overlap")
    if not back_box[1] < front_box[1] < back_box[3]:
        raise BuilderError("selftest: stack must overlap vertically")
    if not front_box[3] > back_box[3]:
        raise BuilderError("selftest: front must extend below the back")
    tt, tb = p["headline_text_box"]
    hy0, hy1 = p["headline_box"]
    if not (hy0 <= tt and tb <= hy1):
        raise BuilderError("selftest: headline text escapes scaled band")
    if abs((tt - hy0) - (hy1 - tb)) > 1:
        raise BuilderError("selftest: headline text not centered")
    with Image.open(out_dir / la_name) as im:
        rgb = im.convert("RGB")
    if near_bg(rgb.getpixel((cx, 0))):
        raise BuilderError("selftest: top row must show bled device")
    if not near_bg(rgb.getpixel((10, 0))):
        raise BuilderError("selftest: top row outside device must stay bg")
    exp_top, exp_bot = p["banner_canvas_rows"]
    if not 0 <= exp_top < exp_bot < hy0:
        raise BuilderError("selftest: banner must sit on-canvas above headline")
    for yy in (exp_top + 10, (exp_top + exp_bot) // 2, exp_bot - 10):
        if near_bg(rgb.getpixel((cx, yy))):
            raise BuilderError(f"selftest: banner row {yy} must show device")
    rows = [tt + _qy(25), tt + _qy(75), tt + _qy(125), tb - _qy(25)]
    if not any(all(c > 200 for c in rgb.getpixel((xx, yy)))
               for yy in rows for xx in scan_xs):
        raise BuilderError("selftest: LA headline must show white text")
    if near_bg(rgb.getpixel((cx, CANVAS_63[1] - 1))):
        raise BuilderError("selftest: bottom row must show bled front")
    if not near_bg(rgb.getpixel((CANVAS_63[0] - 10, CANVAS_63[1] - 1))):
        raise BuilderError("selftest: bottom corner must stay bg")
    if near_bg(rgb.getpixel((cx, back_box[1] + 12))):
        raise BuilderError("selftest: back strip must show device")
    if near_bg(rgb.getpixel((front_box[0] + 16, front_box[1] + _qy(258)))):
        raise BuilderError("selftest: front side strip must show device")
    if not near_bg(rgb.getpixel((10, (top_box[3] + hy0) // 2))):
        raise BuilderError("selftest: top-headline gap must stay bg")
    if not near_bg(rgb.getpixel((10, (hy1 + back_box[1]) // 2))):
        raise BuilderError("selftest: headline-back gap must stay bg")
    lines.append(f"OK {la_name} {p['sha256'][:12]} top={top_box} "
                 f"headline={p['headline_box']} back={back_box} "
                 f"front={front_box} banner={p['banner_canvas_rows']}")
    return lines


def selftest_ipad(out_dir: Path, recipe: dict) -> list[str]:
    lines: list[str] = []
    if recipe["template_version"] != TEMPLATE_IPAD:
        raise BuilderError("selftest: template_version drift")
    for key in ("track", "insights", "history", "add-entry"):
        name = panel_filename(key, recipe["locale"], CANVAS_IPAD)
        p = recipe["panels"][name]
        with Image.open(out_dir / name) as img:
            size = tuple(img.size)
        if size != CANVAS_IPAD:
            raise BuilderError(f"selftest: {name} size drift {size}")
        if sha(out_dir / name) != p["sha256"]:
            raise BuilderError(f"selftest: {name} hash drift vs recipe")
        if p["headline_anchor"] != "top":
            raise BuilderError(f"selftest: {name} headline must be TOP")
        box = p["device_box"]
        if not box[1] - p["headline_box"][1] >= MIN_GAP_IPAD:
            raise BuilderError(f"selftest: {name} headline/device gap")
        if not box[3] + BOTTOM_MIN_IPAD <= CANVAS_IPAD[1]:
            raise BuilderError(f"selftest: {name} bottom margin violated")
        if not (CANVAS_IPAD[0] - (box[2] - box[0])) // 2 >= SIDE_MIN_IPAD:
            raise BuilderError(f"selftest: {name} side margin violated")
        with Image.open(out_dir / name) as im:
            rgb = im.convert("RGB")
        hy0, hy1 = p["headline_box"]
        rows = [hy0 + 25, hy0 + (hy1 - hy0) - 25]
        if not any(all(c > 200 for c in rgb.getpixel((xx, yy)))
                   for yy in rows for xx in range(300, 1765, 40)):
            raise BuilderError(f"selftest: {name} headline must show white text")
        if not near_bg(rgb.getpixel((10, 0))):
            raise BuilderError(f"selftest: {name} top corner must stay bg")
        if near_bg(rgb.getpixel((CANVAS_IPAD[0] // 2, (box[1] + box[3]) // 2))):
            raise BuilderError(f"selftest: {name} device mid must show device")
        lines.append(f"OK {name} {p['sha256'][:12]} "
                     f"headline={p['headline_box']} device={box}")
    return lines


def check_template(recipe: dict, locale: str, size: str) -> list[str]:
    """Byte-identical proof: output hashes MUST equal the approved set.

    The approved sets are pinned to the legacy v13 device art ONLY. A
    recipe composited with a new-version bezel profile (official Apple
    art) is REFUSED here — review sets on new art are never
    byte-compared against historical approvals and no new goldens are
    blessed automatically; explicit owner approval mints new pins.
    """
    profile = recipe.get("bezel", {}).get("profile", "")
    if profile and profile not in (LEGACY_BEZEL_PROFILE_69,
                                   "structural-legacy"):
        raise BuilderError(
            f"template mismatch: bezel profile {profile!r} is a new review "
            "template version with no owner approval (no historical approval "
            "transfer, no auto-approved frozen hash update) — render is a "
            "review set; explicit human approval required before any "
            "byte-identical claim")
    expected = expected_for(locale, size)
    canvas = CANVAS_69 if size == "6.9" else CANVAS_IPAD
    mismatches = []
    for key, want in expected.items():
        name = panel_filename(key, locale, canvas)
        got = recipe["panels"].get(name, {}).get("sha256")
        if got != want:
            mismatches.append(
                f"{name}: got {got} want {want} — output does not reproduce "
                "the approved template; sources or renderer drifted")
    return mismatches
