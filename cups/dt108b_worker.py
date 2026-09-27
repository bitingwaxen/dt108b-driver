#!/usr/bin/env python3
from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
import re
import shutil
import signal
import time
from pathlib import Path

from dt108b.printer import print_file


QUEUE = Path("/private/var/spool/cups/tmp")
FAILED = Path("/Library/Printers/DT108B/jobs/failed")
LOG = Path("/Library/Logs/DT108BWorker.log")
JOB_RE = re.compile(r"^dt108b-\d+_(\d+)_(\d+)\.pdf$")
MAX_FAILED_JOBS = 20
RUNNING = True


def stop(*_args) -> None:
    global RUNNING
    RUNNING = False


def setup_logging() -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(
        LOG,
        maxBytes=2_000_000,
        backupCount=2,
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.handlers.clear()
    root.addHandler(handler)


def trim_failed_jobs() -> None:
    files = sorted(
        (path for path in FAILED.glob("dt108b-*.pdf") if path.is_file()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for old in files[MAX_FAILED_JOBS:]:
        try:
            old.unlink()
        except OSError:
            logging.exception("Could not remove old failed job %s", old)


def process(path: Path) -> None:
    match = JOB_RE.match(path.name)
    copies = int(match.group(2)) if match else 1

    logging.info("Printing %s, copies=%s", path.name, copies)

    try:
        print_file(
            path,
            pages="all",
            copies=copies,
            rotate="auto",
            threshold="auto",
            density="auto",
        )
    except Exception:
        logging.exception("Failed printing %s", path.name)
        FAILED.mkdir(parents=True, exist_ok=True)
        destination = FAILED / path.name
        if destination.exists():
            destination.unlink()
        shutil.move(str(path), str(destination))
        destination.chmod(0o600)
        trim_failed_jobs()
        return

    try:
        path.unlink()
    except FileNotFoundError:
        pass
    logging.info("Completed %s", path.name)


def main() -> None:
    setup_logging()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    FAILED.mkdir(parents=True, exist_ok=True)
    FAILED.chmod(0o700)

    logging.info("DT108B worker started; watching %s", QUEUE)

    while RUNNING:
        jobs = sorted(
            path
            for path in QUEUE.glob("dt108b-*.pdf")
            if path.is_file()
        )

        if not jobs:
            time.sleep(0.25)
            continue

        process(jobs[0])

    logging.info("DT108B worker stopped")


if __name__ == "__main__":
    main()
