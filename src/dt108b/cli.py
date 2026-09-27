from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .diagnose import diagnose
from .printer import print_file


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="dt108b-print",
        description="Direct USB printing for DT108B / 4B-2054F.",
    )
    parser.add_argument("input", type=Path)
    parser.add_argument("--pages", default="all")
    parser.add_argument("--copies", type=int, default=1)
    parser.add_argument(
        "--rotate",
        choices=("auto", "0", "90", "180", "270"),
        default="auto",
    )
    parser.add_argument("--threshold", default="auto")
    parser.add_argument("--density", default="auto")
    parser.add_argument("--delay", type=float, default=0.35)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    def status(current, total, item, copy):
        print(
            f"Printing label {current}/{total}: "
            f"item {item}, copy {copy}"
        )

    def progress(current, total):
        percent = int(current * 100 / total)
        print(f"\rUSB {percent:3d}%", end="", flush=True)
        if current >= total:
            print()

    try:
        result = print_file(
            args.input,
            pages=args.pages,
            copies=args.copies,
            rotate=args.rotate,
            threshold=args.threshold,
            density=args.density,
            delay=args.delay,
            debug=args.debug,
            status_callback=status,
            progress_callback=progress,
        )
        print(f"Printed {result['labels_printed']} label(s).")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


def diagnose_main() -> int:
    print(diagnose())
    return 0
