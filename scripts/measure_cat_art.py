#!/usr/bin/env python3
"""Check and measure one cat breed's sprite art before it replaces the runtime images.

Usage:
    python3 -B scripts/measure_cat_art.py <appearance> [--assets DIR] [--preview OUT_DIR]

<appearance> is orange, cow, blue, siamese or silver. By default the runtime images in
CatLife/Assets.xcassets are read; --assets can point at a folder of new candidate PNGs
named like the runtime ones (cat-blue-walk.png, ...). Nothing is written except optional
preview PNGs with the measured landmarks drawn on them.

The measurements mirror CatAtlasRegistration.swift (alpha bounds, paw-band ground centre)
so the printed Swift values can be pasted into:
  * CatAtlasRegistration.swift  -> `case .<appearance>:` step front/rear paws + baselines
  * CatActor.swift              -> registeredMealContact (<appearance>, 2) / (<appearance>, 3)
Paw and mouth points are heuristics: always confirm them on the preview images.
"""
import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLIPS = {  # name: (columns, rows, expected aspect width/height)
    "avatar": (1, 1, 1.0), "idle": (1, 1, 0.75), "eating": (1, 1, 0.75),
    "expressions": (4, 2, 2.0), "walk": (4, 2, 2.0), "rise": (4, 2, 2.0), "meal": (4, 2, 2.0),
    "play": (4, 2, 2.0), "rest": (2, 4, 0.5), "step": (4, 2, 2.0),
}
REST_ROW_CUTS = [0, 0.285, 0.515, 0.725, 1]  # current CatSpriteLibrary cuts for the rest sheet


def asset_name(appearance, clip):
    return f"cat-{clip}" if appearance == "orange" else f"cat-{appearance}-{clip}"


def load(appearance, clip, assets):
    name = asset_name(appearance, clip)
    candidates = [os.path.join(assets, f"{name}.png")] if assets else []
    candidates.append(os.path.join(ROOT, "CatLife", "Assets.xcassets", f"{name}.imageset", f"{name}.png"))
    for path in candidates:
        if os.path.exists(path):
            return path, Image.open(path).convert("RGBA")
    return None, None


def cells(image, columns, rows, row_cuts=None):
    w, h = image.size
    for row in range(rows):
        top = int(row_cuts[row] * h) if row_cuts else row * h // rows
        bottom = int(row_cuts[row + 1] * h) if row_cuts else (row + 1) * h // rows
        for column in range(columns):
            yield column * w // columns, top, (column + 1) * w // columns, bottom


def register(image, box, scan_left=0):
    """Alpha bounds and paw-band ground centre, as CatAtlasRegistration.extract computes them."""
    left, top, right, bottom = box
    px = image.load()
    xs, ys = [], []
    for y in range(top, bottom):
        for x in range(left + scan_left, right):
            if px[x, y][3] >= 128:
                xs.append(x); ys.append(y)
    if not xs:
        return None
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)
    foot_top = max(min_y, max_y - int((max_y - min_y) * 0.10))
    foot_left = min_x + int((max_x - min_x) * 0.10)
    foot_right = min_x + int((max_x - min_x) * 0.88)
    weighted = weight = 0.0
    for y in range(foot_top, max_y + 1):
        for x in range(foot_left, foot_right + 1):
            r, g, b, a = px[x, y]
            if a < 180 or r <= 100 or g <= r * 0.72 or b <= g * 0.67:
                continue
            amount = 1 + (y - foot_top) / max(1, max_y - foot_top)
            weighted += x * amount; weight += amount
    ground_center = (weighted / weight - left) if weight > 8 else (min_x + max_x) / 2 - left
    min_x = max(left, min_x - 2); max_x = min(right - 1, max_x + 2); min_y = max(top, min_y - 2)
    bounds = (min_x - left, min_y - top, max_x - min_x + 1, max_y - min_y + 1)  # x, y, w, h in cell
    return {"bounds": bounds, "ground_center": ground_center, "ground_y": bounds[1] + bounds[3] - 1}


def edge_leaks(image, box):
    """Opaque pixels on a cell's border mean a neighbour frame will bleed in."""
    left, top, right, bottom = box
    px = image.load()
    leaks = 0
    for x in range(left, right):
        leaks += px[x, top][3] >= 128
        leaks += px[x, bottom - 1][3] >= 128
    for y in range(top, bottom):
        leaks += px[left, y][3] >= 128
        leaks += px[right - 1, y][3] >= 128
    return leaks


def paws(image, box, reg):
    """Lowest opaque pixels in the rear (left) and front (right) thirds of a right-facing cat."""
    left, top, _, _ = box
    bx, by, bw, bh = reg["bounds"]
    px = image.load()

    def lowest(x0, x1):
        for y in range(by + bh - 1, by - 1, -1):
            hits = [x for x in range(x0, x1) if px[left + x, top + y][3] >= 180]
            if hits:
                band = [x for yy in range(max(by, y - 2), y + 1) for x in range(x0, x1)
                        if px[left + x, top + yy][3] >= 180]
                return (round(sum(band) / len(band), 1), y)
        return None
    rear = lowest(bx, bx + int(bw * 0.38))
    front = lowest(bx + int(bw * 0.55), bx + bw)
    return front, rear


def reaching_paw(image, box, reg):
    """Frame 1 names the lifted forepaw: the lowest opaque point of the right-most 22% of the cat."""
    left, top, _, _ = box
    bx, by, bw, bh = reg["bounds"]
    px = image.load()
    x0 = bx + int(bw * 0.78)
    for y in range(by + bh - 1, by - 1, -1):
        hits = [x for x in range(x0, bx + bw) if px[left + x, top + y][3] >= 180]
        if hits:
            return (round(sum(hits) / len(hits), 1), y)
    return None


def mouth(image, box, reg):
    """Lowest opaque point of the head: right 30% of the silhouette, above the paw band."""
    left, top, _, _ = box
    bx, by, bw, bh = reg["bounds"]
    px = image.load()
    x0, limit = bx + int(bw * 0.70), by + bh - int(bh * 0.14)
    for y in range(limit, by - 1, -1):
        hits = [x for x in range(x0, bx + bw) if px[left + x, top + y][3] >= 180]
        if hits:
            return (sum(hits) / len(hits), y)
    return None


def row_gaps(image):
    """Fully transparent horizontal bands nearest 25 / 50 / 75 % (rest sheet row cuts)."""
    w, h = image.size
    px = image.load()
    empty = [all(px[x, y][3] < 128 for x in range(0, w, 2)) for y in range(h)]
    cuts = [0.0]
    for target in (0.25, 0.5, 0.75):
        centre = int(target * h)
        best = None
        for d in range(0, h // 8):
            for y in (centre - d, centre + d):
                if 0 <= y < h and empty[y]:
                    best = y; break
            if best is not None:
                break
        if best is None:
            cuts.append(None); continue
        lo = hi = best
        while lo > 0 and empty[lo - 1]: lo -= 1
        while hi < h - 1 and empty[hi + 1]: hi += 1
        cuts.append(round((lo + hi) / 2 / h, 3))
    return cuts + [1.0]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("appearance", choices=["orange", "cow", "blue", "siamese", "silver"])
    parser.add_argument("--assets", help="folder with candidate PNGs named like the runtime assets")
    parser.add_argument("--preview", help="folder to write annotated preview PNGs")
    args = parser.parse_args()
    problems = 0
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
    print(f"== {args.appearance}")
    for clip, (columns, rows, aspect) in CLIPS.items():
        path, image = load(args.appearance, clip, args.assets)
        if image is None:
            print(f"  MISSING {asset_name(args.appearance, clip)}.png"); problems += 1; continue
        w, h = image.size
        ratio_ok = abs(w / h - aspect) < 0.02
        cuts = REST_ROW_CUTS if clip == "rest" else None
        boxes = list(cells(image, columns, rows, cuts))
        regs = [register(image, b) for b in boxes]
        leaks = sum(edge_leaks(image, b) for b in boxes) if columns * rows > 1 else 0
        empty = sum(r is None for r in regs)
        transparent_corner = image.getpixel((0, 0))[3] == 0
        # Whisker tips touching a cell border are tolerated by the runtime (it scans alpha >= 128),
        # but anything above a few dozen pixels means a body part crosses into the next frame.
        status = "ok" if ratio_ok and not empty and leaks <= 250 and transparent_corner else "CHECK"
        problems += status != "ok"
        print(f"  {clip:12s} {w}x{h} ratio {'ok' if ratio_ok else 'WRONG'}  empty cells {empty}  "
              f"edge-leak px {leaks}  transparent {transparent_corner}  -> {status}")
        if clip == "rest":
            gaps = row_gaps(image)
            same = all(g is not None and abs(g - c) < 0.02 for g, c in zip(gaps, REST_ROW_CUTS))
            print(f"    rest transparent row gaps {gaps}  (code uses {REST_ROW_CUTS}{'' if same else '  -> UPDATE rowCuts'})")
        if clip == "step" and None not in regs:
            front, rear = map(list, zip(*(paws(image, b, r) for b, r in zip(boxes, regs))))
            support_front_1 = front[1]  # the other forepaw still carries the body in frame 1
            front[1] = reaching_paw(image, boxes[1], regs[1]) or front[1]
            # Support plane: the lowest grounded paw, except frames 5/6 where the hind paws are
            # still up on the platform while the forepaws reach down.
            baselines = [rear[i][1] if i in (5, 6) else max(front[i][1], rear[i][1]) for i in range(8)]
            baselines[1] = max(support_front_1[1], rear[1][1])
            print("    step anchors (cell pixels; frame 1 front = lifted paw; confirm on the preview):")
            print("      front = [" + ", ".join(f"CGPoint(x: {p[0]}, y: {p[1]})" for p in front) + "]")
            print("      rear  = [" + ", ".join(f"CGPoint(x: {p[0]}, y: {p[1]})" for p in rear) + "]")
            print(f"      baselines = {baselines}")
            if args.preview:
                draw_preview(image, boxes, args.preview, f"{args.appearance}-step.png",
                             [[f, r] for f, r in zip(front, rear)])
        if clip == "meal" and None not in regs:
            ref_h = regs[0]["bounds"][3]
            unit = 1.20 * 0.91 / ref_h  # CatActor: visualWidth * 1.20 * heightRatio / referenceHeight
            marks = []
            for frame in (2, 3):
                point = mouth(image, boxes[frame], regs[frame])
                if point is None:
                    print(f"    meal frame {frame}: no mouth candidate"); continue
                r = regs[frame]
                ox = (point[0] - r["ground_center"]) * unit
                oy = (r["ground_y"] - point[1]) * unit
                print(f"    meal ({args.appearance}, {frame}): offset = CGPoint(x: {ox:.6f} * visualWidth, "
                      f"y: {oy:.6f} * visualWidth)   [cell px {point[0]:.1f}, {point[1]}]")
                marks.append((frame, point))
            if args.preview:
                per = [[] for _ in boxes]
                for frame, point in marks: per[frame] = [point]
                draw_preview(image, boxes, args.preview, f"{args.appearance}-meal.png", per)
    print("all checks passed" if not problems else f"{problems} item(s) need attention")
    return 1 if problems else 0


def draw_preview(image, boxes, folder, name, points):
    canvas = image.copy()
    draw = ImageDraw.Draw(canvas)
    for (left, top, right, bottom), marks in zip(boxes, points):
        draw.rectangle([left, top, right - 1, bottom - 1], outline=(0, 160, 255, 255))
        for i, p in enumerate(marks):
            if p is None: continue
            x, y = left + p[0], top + p[1]
            color = (255, 40, 40, 255) if i == 0 else (40, 200, 40, 255)
            draw.ellipse([x - 7, y - 7, x + 7, y + 7], outline=color, width=3)
    canvas.save(os.path.join(folder, name))


if __name__ == "__main__":
    sys.exit(main())
