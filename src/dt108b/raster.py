from __future__ import annotations

from pathlib import Path
import fitz
from PIL import Image, ImageOps

from .constants import (
    DPI,
    PDF_HEIGHT,
    PDF_WIDTH,
    RASTER_HEIGHT,
    RASTER_WIDTH,
    WIDTH_BYTES,
    SUPPORTED_IMAGE_EXTENSIONS,
)


def parse_pages(selection: str | None, page_count: int) -> list[int]:
    if selection is None or selection.strip().lower() == "all":
        return list(range(1, page_count + 1))

    pages: list[int] = []

    for part in selection.split(","):
        part = part.strip()
        if not part:
            continue

        if "-" in part:
            start_text, end_text = part.split("-", 1)
            start = int(start_text)
            end = int(end_text)

            if start > end:
                raise ValueError(f"Invalid descending page range: {part}")

            pages.extend(range(start, end + 1))
        else:
            pages.append(int(part))

    pages = list(dict.fromkeys(pages))

    if not pages:
        raise ValueError("No pages selected.")

    for page in pages:
        if page < 1 or page > page_count:
            raise ValueError(
                f"Page {page} is outside the PDF range 1-{page_count}."
            )

    return pages


def resolve_rotation(width: int, height: int, rotate_option: str) -> int:
    if rotate_option != "auto":
        return int(rotate_option)
    return 90 if width > height else 0


def render_pdf_page(
    document: fitz.Document,
    page_number: int,
    rotate_option: str,
) -> Image.Image:
    page = document.load_page(page_number - 1)
    scale = DPI / 72.0

    pixmap = page.get_pixmap(
        matrix=fitz.Matrix(scale, scale),
        colorspace=fitz.csGRAY,
        alpha=False,
        annots=False,
    )

    image = Image.frombytes(
        "L",
        (pixmap.width, pixmap.height),
        pixmap.samples,
    )

    rotation = resolve_rotation(image.width, image.height, rotate_option)
    if rotation:
        image = image.rotate(-rotation, expand=True, fillcolor=255)

    return image


def render_image_file(path: Path, rotate_option: str) -> Image.Image:
    with Image.open(path) as source:
        source = ImageOps.exif_transpose(source)

        if source.mode in ("RGBA", "LA") or (
            source.mode == "P" and "transparency" in source.info
        ):
            rgba = source.convert("RGBA")
            white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            white.alpha_composite(rgba)
            image = white.convert("L")
        else:
            image = source.convert("L")

    rotation = resolve_rotation(image.width, image.height, rotate_option)
    if rotation:
        image = image.rotate(-rotation, expand=True, fillcolor=255)

    return image


def prepare_pdf_canvas(image: Image.Image) -> Image.Image:
    if abs(image.width - PDF_WIDTH) > 3 or abs(image.height - PDF_HEIGHT) > 3:
        raise ValueError(
            f"Expected approximately {PDF_WIDTH}x{PDF_HEIGHT}px for a 4x6 "
            f"PDF label, but got {image.width}x{image.height}px."
        )

    canvas = Image.new("L", (RASTER_WIDTH, RASTER_HEIGHT), 255)
    crop = image.crop(
        (0, 0, min(image.width, PDF_WIDTH), min(image.height, RASTER_HEIGHT))
    )
    canvas.paste(crop, (0, 0))
    return canvas


def prepare_image_canvas(image: Image.Image) -> Image.Image:
    scale = min(PDF_WIDTH / image.width, RASTER_HEIGHT / image.height)
    new_width = max(1, round(image.width * scale))
    new_height = max(1, round(image.height * scale))

    resized = image.resize(
        (new_width, new_height),
        Image.Resampling.LANCZOS,
    )

    canvas = Image.new("L", (RASTER_WIDTH, RASTER_HEIGHT), 255)
    x = (PDF_WIDTH - new_width) // 2
    y = (RASTER_HEIGHT - new_height) // 2
    canvas.paste(resized, (x, y))
    return canvas


def calculate_otsu_threshold(image: Image.Image) -> int:
    histogram = image.convert("L").histogram()
    total_pixels = sum(histogram)

    if total_pixels == 0:
        return 128

    total_sum = sum(value * count for value, count in enumerate(histogram))
    background_weight = 0
    background_sum = 0
    best_variance = -1.0
    best_threshold = 128

    for threshold in range(256):
        count = histogram[threshold]
        background_weight += count

        if background_weight == 0:
            continue

        foreground_weight = total_pixels - background_weight
        if foreground_weight == 0:
            break

        background_sum += threshold * count
        background_mean = background_sum / background_weight
        foreground_mean = (total_sum - background_sum) / foreground_weight

        variance = (
            background_weight
            * foreground_weight
            * (background_mean - foreground_mean) ** 2
        )

        if variance > best_variance:
            best_variance = variance
            best_threshold = threshold

    return max(70, min(best_threshold, 180))


def make_binary(
    image: Image.Image,
    threshold_option: str,
) -> tuple[Image.Image, int]:
    threshold = (
        calculate_otsu_threshold(image)
        if threshold_option == "auto"
        else int(threshold_option)
    )

    if not 0 <= threshold <= 255:
        raise ValueError("threshold must be between 0 and 255")

    binary = image.point(
        lambda pixel: 0 if pixel < threshold else 255,
        mode="1",
    )
    return binary, threshold


def calculate_black_coverage(binary: Image.Image) -> float:
    histogram = binary.convert("L").histogram()
    total_pixels = sum(histogram)
    return 0.0 if total_pixels == 0 else histogram[0] / total_pixels


def resolve_density(
    binary: Image.Image,
    density_option: str,
) -> tuple[int, float]:
    coverage = calculate_black_coverage(binary)

    if density_option != "auto":
        density = int(density_option)
        if not 0 <= density <= 15:
            raise ValueError("density must be between 0 and 15")
        return density, coverage

    if coverage < 0.08:
        density = 9
    elif coverage < 0.16:
        density = 8
    elif coverage < 0.28:
        density = 7
    elif coverage < 0.40:
        density = 6
    else:
        density = 4

    return density, coverage


def pack_windows_driver_format(binary: Image.Image) -> bytes:
    if binary.size != (RASTER_WIDTH, RASTER_HEIGHT):
        raise ValueError(f"Unexpected image size: {binary.size}")

    pixels = binary.load()
    raster = bytearray(WIDTH_BYTES * RASTER_HEIGHT)
    output_index = 0

    for y in range(RASTER_HEIGHT):
        for byte_x in range(WIDTH_BYTES):
            value = 0
            base_x = byte_x * 8

            for bit in range(8):
                # Captured Windows-driver polarity:
                # white pixel = 1, black pixel = 0.
                if pixels[base_x + bit, y] != 0:
                    value |= 1 << (7 - bit)

            raster[output_index] = value
            output_index += 1

    return bytes(raster)
