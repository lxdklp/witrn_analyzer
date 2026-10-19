"""Prepare flat, rounded desktop icons; requires Pillow (python3 -m pip install Pillow)."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


BRANDING = Path(__file__).resolve().parents[1] / "assets" / "branding"
SIZE = 1024
MACOS_ART_SIZE = 832
CORNER_RATIO = 0.22
SUPERSAMPLE = 4


def rounded_artwork(source: Path, size: int) -> Image.Image:
    """Apply an antialiased corner mask, retaining any existing transparency."""
    high_size = size * SUPERSAMPLE
    with Image.open(source) as artwork:
        tile = artwork.convert("RGBA").resize(
            (high_size, high_size), Image.Resampling.LANCZOS
        )
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, high_size - 1, high_size - 1),
        radius=high_size * CORNER_RATIO,
        fill=255,
    )
    tile.putalpha(ImageChops.multiply(tile.getchannel("A"), mask))
    return tile.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    desktop = rounded_artwork(BRANDING / "witrn_analyzer.png", SIZE)
    desktop.save(BRANDING / "witrn_analyzer_windows.png")
    desktop.resize((256, 256), Image.Resampling.LANCZOS).save(
        BRANDING / "witrn_analyzer_linux.png"
    )

    # macOS has independent editable artwork. Never use an already padded
    # output as input, so repeated runs cannot accumulate transparent margins.
    macos_tile = rounded_artwork(
        BRANDING / "witrn_analyzer_macos_artwork.png", MACOS_ART_SIZE
    )
    macos = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    inset = (SIZE - MACOS_ART_SIZE) // 2
    macos.paste(macos_tile, (inset, inset))
    macos.save(BRANDING / "witrn_analyzer_macos.png")
    print("Prepared rounded Windows/Linux icons and macOS icon with 96px margins.")


if __name__ == "__main__":
    main()
