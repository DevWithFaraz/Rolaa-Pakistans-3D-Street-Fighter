import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model2"
OPT_JSON = os.path.join(ROOT, "inspection", "optimization-trial.json")
IMG_IN = os.path.join(ROOT, "inspection", "trial-front-ortho.png")
IMG_OUT = os.path.join(ROOT, "inspection", "mixamo-marker-guide.png")


def world_to_ortho_px(pt, cam):
    w, h = cam["res"]
    scale = cam["ortho_scale"]
    tgt_x, _, tgt_z = cam["tgt"]
    if h >= w:
        span_z = scale
        span_x = scale * (w / h)
    else:
        span_x = scale
        span_z = scale * (h / w)
    px = (0.5 + (pt[0] - tgt_x) / span_x) * w
    py = (0.5 - (pt[2] - tgt_z) / span_z) * h
    return int(round(px)), int(round(py))


def load_font(size):
    for path in (
        r"C:\Windows\Fonts\segoeuib.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\arial.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    with open(OPT_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)

    lm = data["landmarks_world"]
    cam = data["ortho_camera"]
    img = Image.open(IMG_IN).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    font_title = load_font(28)
    font_lbl = load_font(20)
    font_sub = load_font(17)

    # Header banner
    draw.rectangle([(0, 0), (img.width, 84)], fill=(16, 20, 26, 225))
    draw.text((28, 14), "Mixamo Auto-Rigger Marker Guide — Asim Model 2", fill=(255, 255, 255, 255), font=font_title)
    draw.text(
        (28, 50),
        "Symmetry ON  |  Skeleton: Standard Skeleton (65 bones)  |  Place Groin inside tunic at pelvic hinge (z ~ 0.86m)",
        fill=(180, 225, 255, 255),
        font=font_sub,
    )

    markers = [
        ("Chin", lm["chin"], (255, 165, 0, 255), (72, -16)),
        ("Wrists (L/R)", lm["wrist_char_left_posX"], (0, 220, 120, 255), (-125, -46)),
        ("Wrists (L/R)", lm["wrist_char_right_negX"], (0, 220, 120, 255), (-10, -46)),
        ("Elbows (L/R)", lm["elbow_char_left_posX"], (80, 185, 255, 255), (26, -24)),
        ("Elbows (L/R)", lm["elbow_char_right_negX"], (80, 185, 255, 255), (-155, -24)),
        ("Knees (L/R)", lm["knee_char_left_posX"], (255, 95, 160, 255), (30, -10)),
        ("Knees (L/R)", lm["knee_char_right_negX"], (255, 95, 160, 255), (-150, -10)),
        ("Groin (pelvis z=0.86m)", lm["groin"], (255, 65, 65, 255), (36, 18)),
    ]

    for label, pt, col, offset in markers:
        px, py = world_to_ortho_px(pt, cam)
        r = 16
        # Dark outer ring + bright color ring + center dot
        draw.ellipse([(px - r - 2, py - r - 2), (px + r + 2, py + r + 2)], outline=(0, 0, 0, 220), width=5)
        draw.ellipse([(px - r, py - r), (px + r, py + r)], outline=col, width=4)
        draw.ellipse([(px - 4, py - 4), (px + 4, py + 4)], fill=col)

        tx = max(16, min(img.width - 250, px + offset[0]))
        ty = max(92, min(img.height - 46, py + offset[1]))
        bbox = draw.textbbox((tx, ty), label, font=font_lbl)
        pad = 6
        draw.line([(px, py), (tx + (bbox[2] - bbox[0]) // 2, ty + (bbox[3] - bbox[1]) // 2)], fill=col, width=2)
        draw.rounded_rectangle(
            [(bbox[0] - pad, bbox[1] - pad), (bbox[2] + pad, bbox[3] + pad)],
            radius=6,
            fill=(15, 18, 24, 220),
            outline=col,
            width=2,
        )
        draw.text((tx, ty), label, fill=(255, 255, 255, 255), font=font_lbl)

    out = Image.alpha_composite(img, overlay).convert("RGB")
    out.save(IMG_OUT, quality=95)
    print(f"MARKER_GUIDE_SAVED: {IMG_OUT}")


if __name__ == "__main__":
    main()
