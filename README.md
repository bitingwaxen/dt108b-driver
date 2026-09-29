# DT108B Linux AirPrint Driver

Linux/CUPS/AirPrint bridge for the MHT DT108B / 4BARCODE 4B-2054F USB label printer.

Verified hardware identity:

- USB VID/PID: `2d84:7629`
- 203 DPI
- 4 × 6 inch labels
- 816 × 1216 dots

## Architecture

```text
iPhone / AirPrint
       |
       v
CUPS on Debian
       |
       v
dt108b CUPS backend
       |
       v
/var/spool/dt108b/incoming
       |
       v
systemd root worker
       |
       v
PyMuPDF -> bitmap -> PyUSB
       |
       v
DT108B
```

The CUPS backend only spools a PDF. The root worker performs USB access.

## Install

```bash
chmod +x install.sh
sudo ./install.sh
```

Queue: `DT108B_Gap`

Description shown to clients: `DT108B 4x6 Label Printer`

## Test through CUPS

```bash
./scripts/test_print.sh /path/to/label.pdf
```

## Media settings

Supported modes:

- `gap` — ordinary die-cut labels with a transparent gap
- `notch` — side notch/hole labels; uses the transmissive gap sensor
- `continuous` — continuous stock
- `blackmark` — reflective black-mark stock

Default is `gap`, `4 mm`.

Change the server/CUPS default:

```bash
./scripts/set_media.sh gap 4
./scripts/set_media.sh notch 4
./scripts/set_media.sh continuous
./scripts/set_media.sh blackmark 4
```

The PPD also exposes Media Detection, Gap/Notch Size, and Density as CUPS options.
If an iPhone print dialog does not expose vendor-specific options, the server default above is used.

## Sensor calibration

After changing stock you can calibrate:

```bash
./scripts/calibrate.sh gap
./scripts/calibrate.sh notch
./scripts/calibrate.sh blackmark
```

Gap/notch use `GAPDETECT`; black mark uses `BLINEDETECT`.

## AirPrint

The installer shares the CUPS queue and restarts Avahi. Verify discovery with:

```bash
./scripts/verify_airprint.sh
```

The iPhone must be on the same LAN/AP as the Debian print server.

## Logs

```bash
sudo tail -f /var/log/dt108b-worker.log
sudo journalctl -u dt108b-worker -f
```

Failed jobs: `/var/spool/dt108b/failed`

Completed jobs: `/var/spool/dt108b/done`

## Uninstall

```bash
sudo ./uninstall.sh
```

The uninstall removes only DT108B-specific files and leaves CUPS, Avahi, Python and other Debian packages installed so the machine can later host the Epson TM-T88 as well.


## Cold-boot reliability on the isolated Wi-Fi AP

The installer sets the server hostname to `printserver`, ensures that it
resolves locally through:

```text
127.0.1.1 printserver
```

and configures:

```text
HostNameLookups Off
```

in CUPS.

This prevents a cold-boot failure mode where `cupsd` is shown as active and
listening on port 631 but HTTP/IPP requests and `lpstat` hang because the
machine cannot resolve its own hostname on the no-internet print Wi-Fi network.

Quick check:

```bash
getent hosts printserver
curl -m 5 -I http://127.0.0.1:631/
lpstat -p
```
