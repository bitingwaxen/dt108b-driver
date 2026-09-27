from __future__ import annotations

import logging
import re
import shutil
import signal
import time
from pathlib import Path

from .engine import load_config, normalize_mode, print_pdf

INCOMING = Path("/var/spool/dt108b/incoming")
DONE = Path("/var/spool/dt108b/done")
FAILED = Path("/var/spool/dt108b/failed")
LOG = Path("/var/log/dt108b-worker.log")
RUNNING = True

JOB_RE = re.compile(
    r"^dt108b-(?P<stamp>\d+)_(?P<job>\d+)_(?P<copies>\d+)_"
    r"(?P<mode>[A-Za-z0-9_-]+)_(?P<gap>[A-Za-z0-9_.-]+)_"
    r"(?P<density>[A-Za-z0-9_-]+)\.pdf$"
)


def stop(*_args):
    global RUNNING
    RUNNING = False


def decode(path: Path):
    defaults = load_config()
    match = JOB_RE.match(path.name)
    if not match:
        return 1, defaults.media_mode, defaults.gap_mm, defaults.density
    copies = max(1, int(match.group("copies")))
    raw_mode = match.group("mode")
    mode = normalize_mode(None if raw_mode == "default" else raw_mode, defaults.media_mode)
    raw_gap = match.group("gap")
    gap = defaults.gap_mm if raw_gap == "default" else float(raw_gap.lower().replace("mm", ""))
    raw_density = match.group("density")
    density = defaults.density if raw_density == "default" else int(raw_density)
    return copies, mode, gap, density


def process(path: Path):
    copies, mode, gap, density = decode(path)
    logging.info("Printing %s copies=%s mode=%s gap=%s density=%s", path, copies, mode, gap, density)
    try:
        print_pdf(path, copies=copies, media_mode=mode, gap_mm=gap, density=density)
    except Exception:
        logging.exception("Print failed: %s", path)
        FAILED.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), str(FAILED / path.name))
        return
    DONE.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(DONE / path.name))
    logging.info("Completed %s", path)


def main() -> int:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=LOG, level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    for directory in (INCOMING, DONE, FAILED):
        directory.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    logging.info("DT108B worker started")
    while RUNNING:
        jobs = sorted(p for p in INCOMING.glob("dt108b-*.pdf") if p.is_file())
        if jobs:
            process(jobs[0])
        else:
            time.sleep(0.25)
    logging.info("DT108B worker stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
