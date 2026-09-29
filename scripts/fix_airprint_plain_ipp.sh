#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

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

mkdir -p /etc/avahi/services

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

cupsd -t
systemctl restart cups
systemctl restart avahi-daemon
sleep 3

echo "=== Advertised IPP services ==="
avahi-browse -rt _ipp._tcp 2>/dev/null | grep -A12 -B2 -E 'DT108B Gap|DT108B Notch' || true
