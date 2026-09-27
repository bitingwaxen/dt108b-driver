from __future__ import annotations

import configparser
import time
from dataclasses import dataclass
from pathlib import Path

import pymupdf as fitz
import usb.core
import usb.util
from PIL import Image

VID = 0x2D84
PID = 0x7629
INTERFACE = 0
OUT_ENDPOINT = 0x01

DPI = 203
WIDTH_DOTS = 816
HEIGHT_DOTS = 1216
BYTES_PER_ROW = WIDTH_DOTS // 8
CONFIG_PATH = Path("/etc/dt108b/config.ini")


@dataclass
class PrintSettings:
    media_mode: str = "gap"
    gap_mm: float = 4.0
    density: int = 8
    threshold: int = 180
    direction: int = 1
    tear: bool = True


def load_config(path: Path = CONFIG_PATH) -> PrintSettings:
    settings = PrintSettings()
    parser = configparser.ConfigParser()
    if not path.exists():
        return settings
    parser.read(path)
    section = parser["printer"] if parser.has_section("printer") else {}
    settings.media_mode = str(section.get("media_mode", settings.media_mode)).lower()
    settings.gap_mm = float(section.get("gap_mm", settings.gap_mm))
    settings.density = int(section.get("density", settings.density))
    settings.threshold = int(section.get("threshold", settings.threshold))
    settings.direction = int(section.get("direction", settings.direction))
    settings.tear = str(section.get("tear", "true")).lower() in ("1", "true", "yes", "on")
    return settings


def normalize_mode(value: str | None, fallback: str) -> str:
    if not value or value.lower() == "default":
        value = fallback
    key = value.lower().replace("-", "").replace("_", "").replace(" ", "")
    aliases = {
        "gap": "gap",
        "notch": "notch",
        "hole": "notch",
        "continuous": "continuous",
        "blackmark": "blackmark",
    }
    if key not in aliases:
        raise ValueError(f"Unsupported media mode: {value}")
    return aliases[key]


def media_command(mode: str, gap_mm: float) -> str:
    mode = normalize_mode(mode, "gap")
    if mode in ("gap", "notch"):
        # A side notch/hole is read by the same transmissive sensor family.
        return f"GAP {gap_mm:g} mm,0 mm"
    if mode == "continuous":
        return "GAP 0,0"
    if mode == "blackmark":
        return f"BLINE {gap_mm:g} mm,0 mm"
    raise ValueError(mode)


def open_printer():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        raise RuntimeError("DT108B not found (expected USB 2d84:7629)")
    try:
        if dev.is_kernel_driver_active(INTERFACE):
            dev.detach_kernel_driver(INTERFACE)
    except (NotImplementedError, usb.core.USBError):
        pass
    try:
        dev.set_configuration()
    except usb.core.USBError:
        pass
    usb.util.claim_interface(dev, INTERFACE)
    return dev


def close_printer(dev) -> None:
    try:
        usb.util.release_interface(dev, INTERFACE)
    except usb.core.USBError:
        pass
    usb.util.dispose_resources(dev)


def render_page(pdf_path: Path, page_number: int, threshold: int) -> Image.Image:
    doc = fitz.open(pdf_path)
    try:
        page = doc.load_page(page_number)
        scale = DPI / 72.0
        pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), colorspace=fitz.csGRAY, alpha=False)
        image = Image.frombytes("L", (pix.width, pix.height), pix.samples)
    finally:
        doc.close()

    if image.width > image.height:
        image = image.rotate(90, expand=True)
    image.thumbnail((WIDTH_DOTS, HEIGHT_DOTS), Image.Resampling.LANCZOS)
    canvas = Image.new("L", (WIDTH_DOTS, HEIGHT_DOTS), 255)
    x = (WIDTH_DOTS - image.width) // 2
    y = (HEIGHT_DOTS - image.height) // 2
    canvas.paste(image, (x, y))
    return canvas.point(lambda value: 255 if value >= threshold else 0, "1")


def image_to_bitmap(image: Image.Image) -> bytes:
    image = image.convert("1")
    output = bytearray()
    for y in range(HEIGHT_DOTS):
        for byte_x in range(BYTES_PER_ROW):
            value = 0
            for bit in range(8):
                x = byte_x * 8 + bit
                # Proven DT108B polarity: white=1, black=0, MSB leftmost.
                if image.getpixel((x, y)) != 0:
                    value |= 1 << (7 - bit)
            output.append(value)
    return bytes(output)


def send_all(dev, data: bytes, chunk_size: int = 16384) -> None:
    for offset in range(0, len(data), chunk_size):
        chunk = data[offset:offset + chunk_size]
        written = dev.write(OUT_ENDPOINT, chunk, timeout=10000)
        if written != len(chunk):
            raise RuntimeError(f"Short USB write: {written} of {len(chunk)} bytes")


def send_page(dev, bitmap: bytes, *, mode: str, gap_mm: float, copies: int, density: int, direction: int, tear: bool) -> None:
    commands = [
        "SIZE 4 in,6 in",
        media_command(mode, gap_mm),
        f"DENSITY {density}",
        f"DIRECTION {direction}",
        f"SET TEAR {'ON' if tear else 'OFF'}",
        "CLS",
    ]
    prefix = ("\r\n".join(commands) + "\r\n").encode("ascii")
    bitmap_header = f"BITMAP 0,0,{BYTES_PER_ROW},{HEIGHT_DOTS},1,".encode("ascii")
    suffix = f"\r\nPRINT {copies},1\r\n".encode("ascii")
    send_all(dev, prefix)
    send_all(dev, bitmap_header)
    send_all(dev, bitmap)
    send_all(dev, suffix)


def print_pdf(pdf_path: Path, *, copies: int = 1, media_mode: str | None = None, gap_mm: float | None = None, density: int | None = None) -> None:
    defaults = load_config()
    mode = normalize_mode(media_mode, defaults.media_mode)
    gap = defaults.gap_mm if gap_mm is None else float(gap_mm)
    dens = defaults.density if density is None else int(density)

    doc = fitz.open(pdf_path)
    page_count = doc.page_count
    doc.close()

    dev = open_printer()
    try:
        for page_number in range(page_count):
            image = render_page(pdf_path, page_number, defaults.threshold)
            bitmap = image_to_bitmap(image)
            send_page(dev, bitmap, mode=mode, gap_mm=gap, copies=copies, density=dens, direction=defaults.direction, tear=defaults.tear)
            if page_number + 1 < page_count:
                time.sleep(0.7)
    finally:
        close_printer(dev)
