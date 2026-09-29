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

echo "[7/9] Configuring hostname, CUPS, and Avahi..."

PRINTSERVER_HOSTNAME="${PRINTSERVER_HOSTNAME:-printserver}"

# Ensure the local hostname always resolves even when this box is running as
# an isolated Wi-Fi access point with no upstream DNS. Without this, cupsd can
# accept TCP connections on port 631 but block while trying to resolve its own
# hostname after a cold boot.
hostnamectl set-hostname "$PRINTSERVER_HOSTNAME"

python3 - "$PRINTSERVER_HOSTNAME" <<'PY'
from pathlib import Path
import sys

hostname = sys.argv[1]
path = Path("/etc/hosts")
lines = path.read_text().splitlines()

result = []
replaced = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("127.0.1.1"):
        if not replaced:
            result.append(f"127.0.1.1\t{hostname}")
            replaced = True
        continue
    result.append(line)

if not replaced:
    result.append(f"127.0.1.1\t{hostname}")

path.write_text("\n".join(result) + "\n")
PY

# Avoid reverse-DNS lookups for local AirPrint clients. This is important on
# the print server's isolated AP network where no DNS server is advertised.
if grep -qE '^[[:space:]]*HostNameLookups[[:space:]]+' /etc/cups/cupsd.conf; then
  sed -i -E 's/^[[:space:]]*HostNameLookups[[:space:]]+.*/HostNameLookups Off/' /etc/cups/cupsd.conf
else
  printf '\nHostNameLookups Off\n' >> /etc/cups/cupsd.conf
fi

systemctl enable --now cups avahi-daemon
cupsctl --share-printers || true

# Do not let CUPS auto-advertise the queues with TLS/IPPS metadata.
# iOS was able to discover the queues and fetch IPP attributes, but its
# printer-information phase repeatedly terminated the CUPS TLS session.
# We advertise explicit plain-IPP AirPrint records through Avahi instead.
python3 - <<'PY'
from pathlib import Path

path = Path("/etc/cups/cupsd.conf")
lines = path.read_text().splitlines()
result = []
seen_browsing = False
seen_local = False

for line in lines:
    stripped = line.strip().lower()
    if stripped.startswith("browsing "):
        result.append("Browsing No")
        seen_browsing = True
    elif stripped.startswith("browselocalprotocols "):
        result.append("BrowseLocalProtocols none")
        seen_local = True
    else:
        result.append(line)

if not seen_browsing:
    result.append("Browsing No")
if not seen_local:
    result.append("BrowseLocalProtocols none")

path.write_text("\n".join(result) + "\n")
PY

install -d -o root -g root -m 755 /etc/avahi/services

cat > /etc/avahi/services/dt108b-gap.service <<'EOF'
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>DT108B Gap</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/DT108B_Gap</txt-record>
    <txt-record>ty=DT108B 4x6 Label Printer</txt-record>
    <txt-record>product=(DT108B)</txt-record>
    <txt-record>pdl=application/pdf,image/urf,image/pwg-raster</txt-record>
    <txt-record>URF=V1.4,CP1,W8,PQ4,RS203,FN3</txt-record>
    <txt-record>Color=F</txt-record>
    <txt-record>Duplex=F</txt-record>
    <txt-record>note=Gap labels</txt-record>
  </service>
</service-group>
EOF

cat > /etc/avahi/services/dt108b-notch.service <<'EOF'
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>DT108B Notch</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/DT108B_Notch</txt-record>
    <txt-record>ty=DT108B 4x6 Label Printer</txt-record>
    <txt-record>product=(DT108B)</txt-record>
    <txt-record>pdl=application/pdf,image/urf,image/pwg-raster</txt-record>
    <txt-record>URF=V1.4,CP1,W8,PQ4,RS203,FN3</txt-record>
    <txt-record>Color=F</txt-record>
    <txt-record>Duplex=F</txt-record>
    <txt-record>note=Notch / hole labels</txt-record>
  </service>
</service-group>
EOF

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
