#!/usr/bin/env python3
"""Cut the badge sheet into individual transparent PNGs.

`assets-src/badge-icons.png` arrives as one 2048x2048 sheet of six shields on
white. That is fine to look at and useless to build with: an app needs each mark
as its own file, on transparency, trimmed to its own bounds.

The cell boundaries are *found*, not assumed. A hardcoded 3x2 grid would work
until the next sheet has different padding or a seventh badge, and the failure
would be a silently half-cropped icon rather than an error. Instead this finds
the ink, splits it into columns and rows by looking for gaps, and trims each
badge to what it actually occupies.

The background is removed by FLOOD FILL from the border, not by keying on white.
That distinction is the whole reason this file is longer than four lines: every
one of these badges has white *inside* it — the checkmark, the padlock, the
inner outline — and a colour key cannot tell that white from the white around
the shield, so it punches holes through the mark. Only reachability from the
edge separates the two.

Run from the repo root:  python tools/slice-badges.py
"""

from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets-src" / "badge-icons.png"
OUT = ROOT / "brand" / "badges"

# Anything brighter than this in every channel counts as background.
WHITE_CUTOFF = 244
# A run of this many empty rows/columns separates one badge from the next.
GAP = 40
# Transparent margin kept around each trimmed badge, in pixels.
PAD = 8

# Read left-to-right, top-to-bottom. Named for what they DEPICT, not for what a
# screen might use them to mean — the app decides that, and a file called
# "protected.png" would be wrong the first time someone reuses it.
NAMES = [
    "shield-lock-blue",
    "shield-lock-navy",
    "shield-check-green",
    "shield-rules-amber",
    "shield-cross-red",
    "shield-broken-grey",
]


def ink_mask(im: Image.Image) -> list[list[bool]]:
    """True where the pixel is darker than the background."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    return [[any(c < WHITE_CUTOFF for c in px[x, y]) for x in range(w)] for y in range(h)]


def spans(occupied: list[bool], gap: int) -> list[tuple[int, int]]:
    """Turn a per-index occupancy list into (start, end) runs, merging small gaps."""
    runs: list[list[int]] = []
    for i, is_ink in enumerate(occupied):
        if not is_ink:
            continue
        if runs and i - runs[-1][1] <= gap:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    return [(a, b) for a, b in runs]


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"missing {SRC}")

    sheet = Image.open(SRC)
    sheet.load()
    w, h = sheet.size
    mask = ink_mask(sheet)

    rows = spans([any(mask[y]) for y in range(h)], GAP)
    cells: list[tuple[int, int, int, int]] = []
    for top, bottom in rows:
        cols_occupied = [any(mask[y][x] for y in range(top, bottom + 1)) for x in range(w)]
        for left, right in spans(cols_occupied, GAP):
            cells.append((left, top, right, bottom))

    if len(cells) != len(NAMES):
        raise SystemExit(
            f"found {len(cells)} badges but have {len(NAMES)} names — "
            f"the sheet changed shape, so update NAMES rather than guessing"
        )

    OUT.mkdir(parents=True, exist_ok=True)
    rgba = sheet.convert("RGBA")

    for name, (left, top, right, bottom) in zip(NAMES, cells):
        box = (
            max(0, left - PAD),
            max(0, top - PAD),
            min(w, right + 1 + PAD),
            min(h, bottom + 1 + PAD),
        )
        badge = rgba.crop(box)
        badge.putalpha(background_alpha(badge))

        path = OUT / f"{name}.png"
        badge.save(path, "PNG", optimize=True)
        opaque = sum(1 for a in badge.split()[-1].getdata() if a > 250)
        print(
            f"{name:22s} {badge.size[0]}x{badge.size[1]}  "
            f"{path.stat().st_size // 1024}KB  {opaque * 100 // (badge.size[0] * badge.size[1])}% opaque"
        )


def background_alpha(badge: Image.Image) -> Image.Image:
    """Alpha channel where only border-reachable near-white is transparent.

    A breadth-first fill from every near-white pixel on the edge. Whatever it
    cannot reach — the shield fill, and every white detail enclosed by it — stays
    fully opaque, which is exactly the property a colour key does not have.

    The edge is then softened by one pass of averaging, so the anti-aliased
    outline of the original does not become a stair-stepped cut-out.
    """
    from collections import deque

    w, h = badge.size
    px = badge.convert("RGB").load()
    is_pale = [[all(c >= WHITE_CUTOFF for c in px[x, y]) for x in range(w)] for y in range(h)]

    outside = [[False] * w for _ in range(h)]
    queue: deque[tuple[int, int]] = deque()

    for x in range(w):
        for y in (0, h - 1):
            if is_pale[y][x] and not outside[y][x]:
                outside[y][x] = True
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_pale[y][x] and not outside[y][x]:
                outside[y][x] = True
                queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and is_pale[ny][nx] and not outside[ny][nx]:
                outside[ny][nx] = True
                queue.append((nx, ny))

    alpha = Image.new("L", (w, h))
    alpha.putdata([0 if outside[y][x] else 255 for y in range(h) for x in range(w)])
    return alpha.filter(ImageFilter.SMOOTH)


if __name__ == "__main__":
    main()
