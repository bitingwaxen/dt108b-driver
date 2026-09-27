#!/bin/bash
set -euo pipefail

QUEUE_GAP="DT108B_Gap"
QUEUE_NOTCH="DT108B_Notch"
ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then exec sudo "$0" "$@"; fi

echo "[1/9] Installing Debian packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y   cups cups-client cups-filters avahi-daemon avahi-utils   python3 python3-venv python3-pip python3-setuptools python3-usb python3-pil   python3-pymupdf libusb-1.0-0

echo "[2/9] Installing Python runtime..."
mkdir -p /opt/dt108b
rm -rf /opt/dt108b/venv
python3 -m venv --system-site-packages /opt/dt108b/venv
/opt/dt108b/venv/bin/python3 -m pip install --no-deps --no-build-isolation "$ROOT"

echo "[3/9] Installing configuration..."
mkdir -p /etc/dt108b
if [ ! -f /etc/dt108b/config.ini ]; then
  install -m 644 "$ROOT/etc/config.ini" /etc/dt108b/config.ini
fi

echo "[4/9] Creating spool directories..."
install -d -o root -g lp -m 1770 /var/spool/dt108b/incoming
install -d -o root -g root -m 750 /var/spool/dt108b/done
install -d -o root -g root -m 750 /var/spool/dt108b/failed
touch /var/log/dt108b-worker.log
chown root:root /var/log/dt108b-worker.log
chmod 644 /var/log/dt108b-worker.log

echo "[5/9] Installing CUPS backend and PPD..."
install -o root -g root -m 755 "$ROOT/cups/dt108b" /usr/lib/cups/backend/dt108b
install -d -o root -g root -m 755 /usr/share/ppd/dt108b
install -o root -g root -m 644 "$ROOT/cups/DT108B.ppd" /usr/share/ppd/dt108b/DT108B.ppd

echo "[6/9] Installing systemd worker..."
install -o root -g root -m 644 "$ROOT/systemd/dt108b-worker.service" /etc/systemd/system/dt108b-worker.service
systemctl daemon-reload
systemctl enable --now dt108b-worker.service

echo "[7/9] Enabling CUPS and Avahi..."
systemctl enable --now cups avahi-daemon
cupsctl --share-printers || true

echo "[8/9] Creating CUPS queues..."

# Remove the old single-queue name from pre dual-AirPrint builds.
cancel -a DT108B_Labels 2>/dev/null || true
lpadmin -x DT108B_Labels 2>/dev/null || true

for QUEUE in "$QUEUE_GAP" "$QUEUE_NOTCH"; do
  cancel -a "$QUEUE" 2>/dev/null || true
  lpadmin -x "$QUEUE" 2>/dev/null || true
done

lpadmin   -p "$QUEUE_GAP"   -E   -D "DT108B 4x6 — Gap"   -v "dt108b:/usb"   -P "/usr/share/ppd/dt108b/DT108B.ppd"

lpadmin -p "$QUEUE_GAP" -o printer-is-shared=true
lpadmin -p "$QUEUE_GAP" -o PageSize=Label4x6
lpadmin -p "$QUEUE_GAP" -o DTMediaMode=Gap
lpadmin -p "$QUEUE_GAP" -o DTGapSize=4mm
lpadmin -p "$QUEUE_GAP" -o DTDensity=8
cupsenable "$QUEUE_GAP"
cupsaccept "$QUEUE_GAP"

lpadmin   -p "$QUEUE_NOTCH"   -E   -D "DT108B 4x6 — Notch"   -v "dt108b:/usb"   -P "/usr/share/ppd/dt108b/DT108B.ppd"

lpadmin -p "$QUEUE_NOTCH" -o printer-is-shared=true
lpadmin -p "$QUEUE_NOTCH" -o PageSize=Label4x6
lpadmin -p "$QUEUE_NOTCH" -o DTMediaMode=Notch
lpadmin -p "$QUEUE_NOTCH" -o DTGapSize=4mm
lpadmin -p "$QUEUE_NOTCH" -o DTDensity=8
cupsenable "$QUEUE_NOTCH"
cupsaccept "$QUEUE_NOTCH"

systemctl restart cups avahi-daemon
sleep 2

echo "[9/9] Verifying..."
echo "USB:"
lsusb | grep -i '2d84:7629' || echo "WARNING: DT108B USB 2d84:7629 not currently visible"
echo
echo "Worker:"
systemctl --no-pager --full status dt108b-worker.service | head -20 || true
echo
echo "Printers:"
lpstat -p "$QUEUE_GAP" -l
lpstat -p "$QUEUE_NOTCH" -l
lpstat -v "$QUEUE_GAP"
lpstat -v "$QUEUE_NOTCH"
echo
echo "Defaults:"
lpoptions -p "$QUEUE_GAP"
lpoptions -p "$QUEUE_NOTCH"
echo
echo "AirPrint discovery:"
avahi-browse -rt _universal._sub._ipp._tcp 2>/dev/null | grep -A12 -B2 -i DT108B || true

echo
echo "Installation complete."
echo "Test with: $ROOT/scripts/test_print.sh /path/to/label.pdf"
