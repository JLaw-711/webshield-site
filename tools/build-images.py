#!/usr/bin/env python3
"""Turn the source photographs into the sizes and formats the page actually serves.

The originals are multi-megabyte PNGs. Nothing on the page needs an alpha channel or a
lossless codec, and a 4 MB hero is the single easiest way to make a "fast, quiet" product
feel slow. Each source becomes a WebP (what almost everyone gets) and a JPEG (what the
rest get), at twice its rendered size so it stays sharp on a phone.

Run from the repo root:  python tools/build-images.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets-src"
OUT = ROOT / "public" / "assets" / "img"

# name -> (source file, output width, output height)
# Heights are 2x the CSS pixel size the page renders them at.
TARGETS = {
    # Rendered at ~576x280 in the two-up pillar cards.
    "kids-card": ("family-kids.png", 1152, 560),
    "you-card": ("woman-cafe.png", 1152, 560),
    # Full-bleed band, at the source's own 1.79:1 rather than a wider crop.
    #
    # Deliberately NOT upscaled. The source is 1376x768 and the band renders at
    # most ~1440x420, so a "2x" output would be 2880px of invented pixels: LANCZOS
    # cannot add detail that is not there, and the browser's own upscale from the
    # native file looks the same for a third of the bytes. It also sits under a
    # heavy dark gradient with text over it, which is the most forgiving place on
    # the page for a soft pixel.
    #
    # The band crops HEIGHT (object-fit: cover on a very wide box), so where the
    # crop lands matters more than the size. Both faces sit in the upper-middle of
    # this frame, which is why site.css pins object-position to 40% rather than
    # letting a centre crop take the father's head off.
    "family-band": ("family-banner.png", 1376, 768),
}

QUALITY_WEBP = 82
QUALITY_JPEG = 84


def cover(im: Image.Image, width: int, height: int) -> Image.Image:
    """Scale-and-centre-crop, the same geometry as CSS `object-fit: cover`."""
    src_w, src_h = im.size
    scale = max(width / src_w, height / src_h)
    resized = im.resize(
        (round(src_w * scale), round(src_h * scale)), Image.Resampling.LANCZOS
    )
    left = (resized.width - width) // 2
    top = (resized.height - height) // 2
    return resized.crop((left, top, left + width, top + height))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (source, width, height) in TARGETS.items():
        path = SRC / source
        if not path.exists():
            raise SystemExit(f"missing source image: {path}")

        im = Image.open(path)
        im.load()
        # Flatten onto white: the sources carry alpha, JPEG cannot, and a transparent
        # pixel silently becomes black rather than the page background.
        if im.mode in ("RGBA", "LA", "P"):
            flat = Image.new("RGB", im.size, (255, 255, 255))
            rgba = im.convert("RGBA")
            flat.paste(rgba, mask=rgba.split()[-1])
            im = flat
        else:
            im = im.convert("RGB")

        out = cover(im, width, height)
        webp = OUT / f"{name}.webp"
        jpeg = OUT / f"{name}.jpg"
        out.save(webp, "WEBP", quality=QUALITY_WEBP, method=6)
        out.save(jpeg, "JPEG", quality=QUALITY_JPEG, optimize=True, progressive=True)
        print(
            f"{name:12s} {width}x{height}  "
            f"webp {webp.stat().st_size // 1024}KB  jpeg {jpeg.stat().st_size // 1024}KB"
        )


if __name__ == "__main__":
    main()
