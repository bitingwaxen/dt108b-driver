from __future__ import annotations
from .constants import WIDTH_BYTES, RASTER_HEIGHT


def build_print_job(raster: bytes, density: int) -> bytes:
    expected = WIDTH_BYTES * RASTER_HEIGHT

    if len(raster) != expected:
        raise ValueError(
            f"Raster is {len(raster)} bytes; expected {expected}."
        )

    header = (
        "SET TEAR ON\r\n"
        f"DENSITY {density}\r\n"
        "CLS\r\n"
        f"BITMAP 0,1,{WIDTH_BYTES},{RASTER_HEIGHT},1,"
    ).encode("ascii")

    return header + raster + b"\r\nPRINT 1,1\r\n"
