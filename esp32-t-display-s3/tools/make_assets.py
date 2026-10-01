"""Prepare small display images without changing the macOS originals.

Run: uv run --with pillow python tools/make_assets.py
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent.parent
SOURCE = HERE.parent / "dsh-balance-pet-macos" / "Resources"
OUTPUT = HERE / "data"
IMAGES = {
    "deepseek": "sprite.png",
    "deepseek-offline": "sprite-deepseek-offline.png",
    "gpt": "sprite-gpt.png",
    "claude": "sprite-claude.png",
    "gemini": "sprite-gemini.png",
}


def main():
    OUTPUT.mkdir(exist_ok=True)
    for name, source_name in IMAGES.items():
        source = Image.open(SOURCE / source_name).convert("RGBA")
        source.thumbnail((255, 170), Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", (320, 170), (18, 23, 42))
        x = (320 - source.width) // 2
        canvas.paste(source, (x, (170 - source.height) // 2), source)
        # The 1.9-inch LCD reads darker than the desktop preview. Lift shadows
        # gently while keeping the tablet's pure black area black.
        gamma = 0.85
        lut = [round(255 * (value / 255) ** gamma) for value in range(256)]
        canvas = canvas.point(lut * 3)
        output = OUTPUT / f"{name}.jpg"
        canvas.save(output, "JPEG", quality=78, optimize=True, progressive=False, subsampling=0)
        print(f"{source_name}: {output.stat().st_size:,} bytes -> {output.name}")

    # Layout simulation only; the real display is rendered by the firmware.
    preview = Image.open(OUTPUT / "deepseek.jpg").convert("RGB")
    font = ImageFont.load_default()
    ImageDraw.Draw(preview).text((226, 126), "38.62", font=font, fill="white")
    preview_dir = HERE / "docs"
    preview_dir.mkdir(exist_ok=True)
    preview.resize((960, 510), Image.Resampling.NEAREST).save(preview_dir / "layout-demo.png")
    montage = Image.new("RGB", (640, 340), (18, 23, 42))
    for index, name in enumerate(("deepseek", "gpt", "claude", "gemini")):
        tile = Image.open(OUTPUT / f"{name}.jpg").convert("RGB")
        ImageDraw.Draw(tile).text((226, 126), "38.62", font=font, fill="white")
        montage.paste(tile, ((index % 2) * 320, (index // 2) * 170))
    montage.resize((1280, 680), Image.Resampling.NEAREST).save(preview_dir / "four-characters-demo.png")


if __name__ == "__main__":
    main()
