# Changelog

## 1.2.0 — 2026-08-02

- Final tested Chrome/CUPS architecture
- CUPS backend writes atomically into CUPS's own `TMPDIR`
- Root launchd worker watches only `dt108b-*.pdf` files
- Successful label PDFs are deleted after printing for privacy
- Failed jobs are retained with restricted permissions, capped at 20 files
- Complete clean-removal script covers every development revision
- Optional force cleanup for untracked Homebrew dependencies from old builds
- Idempotent installer records whether Homebrew dependencies were pre-existing
- Explicit Homebrew libusb lookup for launchd reliability
- Removed obsolete GUI and direct-CUPS Python execution paths

## 1.1.x — development builds

Development releases established the spool-worker architecture and identified
two macOS CUPS sandbox constraints: backends cannot execute the Python/USB
stack reliably, and the backend must write directly into the supplied CUPS
temporary directory rather than a custom subdirectory.
