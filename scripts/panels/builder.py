#!/usr/bin/env python3
"""Store marketing panel builder (task 9.x): approved templates as code.

Promotion of the retained `panels/` builders into git (text only — no
binaries). Two owner-approved compositions are encoded here, byte-exact:

- 6.9-inch iPhone (1320x2868), template v13: four singles (Track, Insights,
  History, Add-entry) with headline TOP + one LA-combined panel using the
  v11 owner-Figma geometry verbatim. Approved 2026-11-02 (composition only).
- 13-inch iPad (2064x2752), template ipad-v1: four singles, headline TOP,
  silver-bezel device, NO LA panel (iPad has no Island presentations and
  the owner scoped LA out of the iPad set). Approved 2026-11-02
  (composition only).

A 6.5-inch composition was never owner-approved: `--size 6.5` is
recognized but refused loudly at the template gate (see panels.py).

Rendering core is a behavior-preserving port of the retained
`build_final_v13.py` (6.9) and `ipad/build_ipad_panels_v1.py` (iPad)
lineages: same constants, same geometry, same fonts, same resampling,
same PNG save defaults. With `--locale en --size 6.9` and the retained
v13 sources, outputs MUST be byte-identical to the five approved v13
PNGs (see EXPECTED_EN69; enforced by `--check-template`).

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
CANVAS_IPAD = (2064, 2752)

SIZES = {
    "6.9": {"canvas": CANVAS_69, "template": TEMPLATE_69},
    "6.5": {"canvas": (1242, 2688), "template": None},  # gated: never approved
    "ipad13": {"canvas": CANVAS_IPAD, "template": TEMPLATE_IPAD},
}

# --- Matrix + bezel-asset contract (data only; rendering untouched) --------
#
# Canonical bezel filenames shared by fetch_bezel_assets.py (writer) and
# panels.py --render-matrix (reader). The PNG bytes themselves live in
# external retention, never in git.
BEZEL_FILE_69 = "iphone-69-bezel.png"
BEZEL_FILE_IPAD = "ipad-13-bezel.png"
BEZEL_FILES = {"6.9": BEZEL_FILE_69, "ipad13": BEZEL_FILE_IPAD}

# CI device keys (see the app-screenshots workflow device catalog) mapped
# to the panel size contract. iphone65/iphone63 carry no owner-approved
# panel composition: the matrix records them BLOCKED at the template gate
# (same refusal as --size 6.5), never rendered, never stretched.
MATRIX_DEVICES = {
    "iphone69": {"size": "6.9", "canvas": (1320, 2868), "island": True},
    "iphone63": {"size": "6.3", "canvas": (1206, 2622), "island": True},
    "iphone65": {"size": "6.5", "canvas": (1242, 2688), "island": False},
    "ipad13": {"size": "ipad13", "canvas": (2064, 2752), "island": False},
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


# ---------------------------------------------------------------------------
# Source + bezel verification (fail-closed; no stretching, no tampering)
# ---------------------------------------------------------------------------

def verify_sources(frames_dir: Path, manifest_path: Path,
                   needed: tuple[str, ...],
                   canvas: tuple[int, int]) -> tuple[dict, dict]:
    try:
        manifest = json.loads(manifest_path.read_bytes().decode("utf-8"))
    except OSError as exc:
        raise BuilderError(f"run manifest not readable {manifest_path}: {exc}")
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BuilderError(f"run manifest malformed {manifest_path}: {exc}")
    if not isinstance(manifest, dict) or not isinstance(manifest.get("frames"), list):
        raise BuilderError(f"run manifest {manifest_path} missing 'frames' list")
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


def verify_bezel_69(bezel_path: Path) -> dict:
    if not bezel_path.is_file():
        raise BuilderError(f"missing bezel asset {bezel_path}")
    with Image.open(bezel_path) as im:
        size, bands, mode = tuple(im.size), im.getbands(), im.mode
    if size != BEZEL69_NATIVE:
        raise BuilderError(f"bezel size drift {size} != {BEZEL69_NATIVE}")
    if "A" not in bands:
        raise BuilderError("bezel must carry alpha (transparent screen)")
    sw, sh = BEZEL69_SLOT
    if (sw, sh) != (880, 1912):
        raise BuilderError("screen slot drift")
    if sw * CANVAS_69[1] != sh * CANVAS_69[0]:
        raise BuilderError("screen slot aspect drift")
    x, y = BEZEL69_AT
    if x + sw > BEZEL69_NATIVE[0] or y + sh > BEZEL69_NATIVE[1]:
        raise BuilderError("screen slot overflow")
    return {"sha256": sha(bezel_path), "size": list(size), "mode": mode}


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


# ---------------------------------------------------------------------------
# 6.9 rendering (verbatim v13 geometry)
# ---------------------------------------------------------------------------

def load_bezel(bezel_path: Path) -> Image.Image:
    with Image.open(bezel_path) as im:
        return im.convert("RGBA")


def device_shot_69(src: Image.Image, bezel: Image.Image) -> Image.Image:
    if tuple(src.size) != CANVAS_69:
        raise BuilderError(
            f"cross-size art rejected: {src.size} vs canvas {CANVAS_69}")
    shot = src.resize(BEZEL69_SLOT, Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", BEZEL69_SLOT, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, *BEZEL69_SLOT], radius=BEZEL69_MASK_R, fill=255)
    shot.putalpha(mask)
    dev = Image.new("RGBA", BEZEL69_NATIVE, (0, 0, 0, 0))
    dev.paste(shot, BEZEL69_AT, shot)
    dev.alpha_composite(bezel)
    return dev


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
            "screen_slot_px": list(BEZEL69_SLOT),
            "screen_at_px": list(BEZEL69_AT),
            "screen_mask_radius_px": BEZEL69_MASK_R,
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
    src_hashes, run_meta = verify_sources(frames_dir, manifest_path,
                                          needed, CANVAS_IPAD)
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
    """Byte-identical proof: output hashes MUST equal the approved set."""
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
