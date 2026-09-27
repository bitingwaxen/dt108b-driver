from __future__ import annotations

import argparse
from pathlib import Path
from .engine import close_printer, load_config, open_printer, print_pdf, send_all


def print_main() -> int:
    parser = argparse.ArgumentParser(description="Print a PDF directly on DT108B")
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--mode", choices=["gap", "notch", "continuous", "blackmark"], default=None)
    parser.add_argument("--gap-mm", type=float, default=None)
    parser.add_argument("--copies", type=int, default=1)
    parser.add_argument("--density", type=int, default=None)
    args = parser.parse_args()
    print_pdf(args.pdf, copies=args.copies, media_mode=args.mode, gap_mm=args.gap_mm, density=args.density)
    return 0


def calibrate_main() -> int:
    parser = argparse.ArgumentParser(description="Calibrate DT108B media sensor")
    parser.add_argument("--mode", choices=["gap", "notch", "blackmark"], default=None)
    args = parser.parse_args()
    mode = args.mode or load_config().media_mode
    if mode in ("gap", "notch"):
        command = b"GAPDETECT\r\n"
    elif mode == "blackmark":
        command = b"BLINEDETECT\r\n"
    else:
        raise SystemExit("Continuous media does not use sensor calibration")
    dev = open_printer()
    try:
        send_all(dev, command)
    finally:
        close_printer(dev)
    print(f"Calibration command sent for mode: {mode}")
    return 0
