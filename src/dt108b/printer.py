from __future__ import annotations

import time
from pathlib import Path
import fitz

from .constants import SUPPORTED_IMAGE_EXTENSIONS
from .raster import (
    parse_pages,
    render_pdf_page,
    render_image_file,
    prepare_pdf_canvas,
    prepare_image_canvas,
    make_binary,
    resolve_density,
    pack_windows_driver_format,
)
from .tspl import build_print_job
from .usb import USBPrinter


def prepare_jobs(
    source: Path,
    pages: str = "all",
    rotate: str = "auto",
):
    suffix = source.suffix.lower()

    if suffix == ".pdf":
        document = fitz.open(source)
        try:
            selected_pages = parse_pages(pages, document.page_count)
            jobs = []

            for page_number in selected_pages:
                rendered = render_pdf_page(document, page_number, rotate)
                jobs.append((page_number, prepare_pdf_canvas(rendered)))

            return jobs
        finally:
            document.close()

    if suffix in SUPPORTED_IMAGE_EXTENSIONS:
        rendered = render_image_file(source, rotate)
        return [(1, prepare_image_canvas(rendered))]

    raise ValueError("Supported formats are PDF, PNG, JPG, and JPEG.")


def print_file(
    source: str | Path,
    *,
    pages: str = "all",
    copies: int = 1,
    rotate: str = "auto",
    threshold: str = "auto",
    density: str = "auto",
    delay: float = 0.35,
    debug: bool = False,
    progress_callback=None,
    status_callback=None,
) -> dict:
    source = Path(source).expanduser().resolve()

    if not source.exists():
        raise FileNotFoundError(source)

    if copies < 1:
        raise ValueError("copies must be at least 1")

    jobs = prepare_jobs(source, pages=pages, rotate=rotate)
    total_labels = len(jobs) * copies
    completed = 0
    details = []

    with USBPrinter() as printer:
        for source_index, canvas in jobs:
            binary, selected_threshold = make_binary(canvas, threshold)
            selected_density, black_coverage = resolve_density(binary, density)

            if debug:
                stem = source.with_suffix("")
                canvas.save(f"{stem}-item-{source_index:03d}-gray.png")
                binary.convert("L").save(
                    f"{stem}-item-{source_index:03d}-sent.png"
                )

            raster = pack_windows_driver_format(binary)
            payload = build_print_job(raster, selected_density)

            for copy_number in range(1, copies + 1):
                if status_callback:
                    status_callback(
                        completed + 1,
                        total_labels,
                        source_index,
                        copy_number,
                    )

                printer.write_all(payload, progress_callback)
                completed += 1

                details.append(
                    {
                        "item": source_index,
                        "copy": copy_number,
                        "threshold": selected_threshold,
                        "density": selected_density,
                        "black_coverage": black_coverage,
                    }
                )

                if completed < total_labels:
                    time.sleep(delay)

    return {
        "source": source,
        "labels_printed": completed,
        "details": details,
    }
