#!/usr/bin/env python3
"""Render a PNG mock-up of the in-game table from a layout dump.

The headless Godot build in CI has no rendering backend, so this reconstructs
the composition from `Tests/DumpLayout.gd` output using the real card art. It
is a review aid for checking spacing and overlap, not a pixel-exact renderer.

    godot --no-window -s Tests/DumpLayout.gd
    python3 Tools/preview_layout.py --out preview.png
"""

from __future__ import annotations

import argparse
import json
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  pip install pillow")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "Assets", "Uno Game Assets")
DEFAULT_DUMP = os.path.expanduser(
    "~/.local/share/godot/app_userdata/UNO/layout_dump.json"
)

CARD_W, CARD_H = 388, 562
FELT = (18, 66, 44)


def vec(value) -> tuple[float, float]:
    if isinstance(value, dict):
        return float(value["x"]), float(value["y"])
    return float(value[0]), float(value[1])


def load_font(size: int, weight: str = "Medium"):
    path = os.path.join(REPO, "Assets", "Roboto", f"Roboto-{weight}.ttf")
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def card_image(key: str, cache: dict) -> Image.Image | None:
    if key in cache:
        return cache[key]
    path = os.path.join(ASSETS, f"{key}.png")
    image = None
    if os.path.exists(path):
        image = Image.open(path).convert("RGBA")
    cache[key] = image
    return image


def paste_card(canvas, image, center, rotation, scale):
    """Place one card, rotated about its centre."""
    width = max(int(CARD_W * scale), 1)
    height = max(int(CARD_H * scale), 1)
    sprite = image.resize((width, height), Image.LANCZOS)
    if abs(rotation) > 0.01:
        sprite = sprite.rotate(-rotation, resample=Image.BICUBIC, expand=True)

    # Soft drop shadow so overlapping cards stay readable.
    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (0, 0), sprite.split()[-1])
    ox = int(center[0] - sprite.width / 2)
    oy = int(center[1] - sprite.height / 2)
    canvas.alpha_composite(shadow, (ox + 4, oy + 7))
    canvas.alpha_composite(sprite, (ox, oy))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", default=DEFAULT_DUMP)
    parser.add_argument("--out", default=os.path.join(REPO, "docs", "images", "table-preview.png"))
    parser.add_argument("--table", type=int, default=None, help="table variant 0-4")
    args = parser.parse_args()

    if not os.path.exists(args.dump):
        sys.exit(f"no dump at {args.dump}\nrun: godot --no-window -s Tests/DumpLayout.gd")

    with open(args.dump) as handle:
        data = json.load(handle)

    width, height = (int(v) for v in vec(data["viewport"]))
    canvas = Image.new("RGBA", (width, height), FELT + (255,))

    variant = args.table if args.table is not None else data.get("table_variant", 0)
    table_path = os.path.join(ASSETS, f"Table_{variant}.png")
    if os.path.exists(table_path):
        canvas.alpha_composite(
            Image.open(table_path).convert("RGBA").resize((width, height), Image.LANCZOS)
        )

    cache: dict = {}
    draw = ImageDraw.Draw(canvas)

    # Deck stack.
    back = card_image("Card_Back", cache) or card_image("Deck", cache)
    scale = data.get("card_scale", 0.34)
    if back is not None and "deck_position" in data:
        cx, cy = vec(data["deck_position"])
        for i in range(4, -1, -1):
            paste_card(canvas, back, (cx - i * 1.5, cy - i * 3.0), 0.0, scale)

    # Discard pile, then hands, in the engine's own z-order.
    for entry in data.get("discards", []):
        image = card_image(entry.get("asset", ""), cache)
        if image is not None:
            paste_card(canvas, image, vec(entry["position"]),
                       entry.get("rotation", 0.0), entry.get("scale", scale))

    for entry in sorted(data.get("cards", []), key=lambda c: c.get("z", 0)):
        key = entry.get("asset", "")
        image = card_image(key, cache) if not entry.get("face_down") else back
        if image is None:
            image = back
        if image is not None:
            paste_card(canvas, image, vec(entry["position"]),
                       entry.get("rotation", 0.0), entry.get("scale", scale))

    hud = data.get("hud", {})
    font_small = load_font(15)
    font_body = load_font(17)
    font_bold = load_font(16, "Bold")

    def panel(box, radius=14, fill=(12, 15, 23, 200), outline=(255, 255, 255, 32)):
        draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=2)

    # Seat plates.
    for seat in hud.get("seats", []):
        x, y = vec(seat["position"])
        w, h = vec(seat["size"])
        panel([x, y, x + w, y + h])
        draw.text((x + w / 2, y + h / 2), seat.get("text", ""),
                  font=font_bold, fill=(240, 244, 252), anchor="mm")

    # Buttons.
    for button in hud.get("buttons", []):
        if not button.get("visible", True):
            continue
        x, y = vec(button["position"])
        w, h = vec(button["size"])
        disabled = button.get("disabled", False)
        label = button.get("text", "")
        fill = (30, 35, 48, 210) if disabled else (44, 54, 76, 240)
        if label == "UNO!" and not disabled:
            fill = (196, 132, 22, 245)
        if label == "CATCH!" and not disabled:
            fill = (178, 46, 58, 245)
        panel([x, y, x + w, y + h], radius=12, fill=fill)
        draw.text((x + w / 2, y + h / 2), label, font=font_bold,
                  fill=(120, 128, 145) if disabled else (245, 247, 252), anchor="mm")

    # Status banner and readouts, using the engine's own rectangles.
    rects = hud.get("rects", {})

    def rect_of(name):
        entry = rects.get(name)
        if not entry:
            return None
        x, y = vec(entry["position"])
        w, h = vec(entry["size"])
        return [x, y, x + w, y + h]

    status = hud.get("status", "")
    box = rect_of("status")
    if status and box:
        panel(box, radius=16)
        draw.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), status,
                  font=font_body, fill=(238, 242, 250), anchor="mm")

    box = rect_of("deck_counts")
    if box:
        for i, line in enumerate(hud.get("deck_label", "").split("\n")):
            draw.text((box[0], box[1] + 4 + i * 19), line, font=font_small,
                      fill=(214, 222, 236), anchor="lt")

    box = rect_of("score")
    if box:
        for i, line in enumerate(hud.get("score_label", "").split("\n")):
            draw.text((box[2], box[1] + 4 + i * 19), line, font=font_small,
                      fill=(214, 222, 236), anchor="rt")

    color_name = data.get("active_color_name", "")
    box = rect_of("color_chip")
    if color_name and box:
        swatch = {"Red": (198, 40, 40), "Blue": (25, 96, 190),
                  "Green": (38, 140, 62), "Yellow": (222, 176, 24)}.get(color_name, (90, 90, 90))
        panel(box, radius=12, fill=swatch + (238,))
        draw.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2),
                  hud.get("color_label", color_name.upper()),
                  font=font_bold, fill=(255, 255, 255), anchor="mm")

    box = rect_of("direction")
    if box:
        panel(box, radius=12)
        draw.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2),
                  hud.get("direction", ""), font=font_bold,
                  fill=(238, 242, 250), anchor="mm")

    box = rect_of("stack")
    if box and hud.get("stack_visible"):
        panel(box, radius=12, fill=(150, 40, 34, 240))
        draw.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2),
                  hud.get("stack_text", ""), font=font_bold,
                  fill=(255, 236, 232), anchor="mm")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    canvas.convert("RGB").save(args.out, quality=94)
    print(f"wrote {args.out}  ({width}x{height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
