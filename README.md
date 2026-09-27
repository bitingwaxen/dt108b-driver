# DT108B macOS Driver — Final 1.2.0

Direct USB printing and a macOS virtual printer for:

- **MHT DT108B**
- **4BARCODE 4B-2054F**
- compatible rebrands using USB **VID `0x2D84` / PID `0x7629`**

This release contains the exact architecture verified to print from both the
macOS Terminal and Chrome.

## Working architecture

```text
Chrome / Preview / Acrobat
          ↓
         CUPS
          ↓
/private/var/spool/cups/tmp/dt108b-*.pdf
          ↓
   root launchd worker
          ↓
   direct libusb/TSPL output
          ↓
       DT108B
```

The CUPS backend is deliberately shell-only. It writes the PDF directly into
the CUPS-provided `TMPDIR`, using a hidden temporary file followed by an
atomic rename. Python and USB access happen only in the launchd worker,
outside the CUPS sandbox.

## Clean installation

1. Optionally remove every previous DT108B development installation:

   ```bash
   ./remove_everything.sh
   ```

2. Install the final project:

   ```bash
   ./install.sh
   ```

The installer requests administrator access, installs Homebrew
`python@3.12` and `libusb` when necessary, creates an isolated virtual
environment, installs the CUPS queue, and starts the worker.

## Printing from Chrome

1. Open the shipping-label PDF.
2. Press **Command-P**.
3. Select **DT108B Direct**.
4. Select **4 × 6 in** paper.
5. Print.

The CUPS warning that traditional printer drivers are deprecated is expected
on current macOS CUPS. It does not indicate an installation failure.

## Test the CUPS path

```bash
./scripts/test_print.sh /path/to/label.pdf
```

## Direct command-line printing

```bash
dt108b-print /path/to/label.pdf
dt108b-print labels.pdf --pages 1,3-5
dt108b-print labels.pdf --copies 2
dt108b-print label.png
```

## Diagnostics

```bash
dt108b-diagnose
./scripts/collect_diagnostics.sh
```

Worker log:

```text
/Library/Logs/DT108BWorker.log
```

Failed PDFs are stored with mode `600` in:

```text
/Library/Printers/DT108B/jobs/failed
```

Successful queued PDFs are deleted after printing. Clear retained failures:

```bash
./scripts/clear_failed_jobs.sh
```

## Complete removal

```bash
./remove_everything.sh
```

This removes all DT108B queues, services, backends, filters, PPDs, runtimes,
CLI links, logs, old GUI artifacts, and every spool location used during
development.

Homebrew `python@3.12` and `libusb` are left installed by default because
other applications may share them. The final installer records whether it
installed those packages. To remove packages recorded as installed by this
project, when no installed Homebrew formula depends on them:

```bash
./remove_everything.sh --remove-homebrew-deps
```

For old development installations that predate dependency tracking, an explicit
force mode is available. It still refuses to remove a formula when another
installed Homebrew formula depends on it:

```bash
./remove_everything.sh --force-remove-homebrew-deps
```

## Installed paths

```text
/Library/Printers/DT108B
/Library/LaunchDaemons/com.pickybear.dt108b-worker.plist
/usr/libexec/cups/backend/dt108b
/Library/Printers/PPDs/Contents/Resources/DT108B.ppd
/usr/local/bin/dt108b-print
/usr/local/bin/dt108b-diagnose
```

CUPS queue: `DT108B_Direct`  
Device URI: `dt108b:/direct`

## Raster protocol

The working Windows driver sends:

```text
SET TEAR ON
DENSITY <automatic value>
CLS
BITMAP 0,1,102,1216,1,<124032 raster bytes>
PRINT 1,1
```

Raster details:

- 816 dots wide, 1216 rows
- 203 DPI
- white pixel = bit `1`
- black pixel = bit `0`
- MSB is the leftmost pixel

## Requirements

- macOS
- native Homebrew installation
- USB-connected compatible printer
- 4 × 6 inch labels

## License

MIT
