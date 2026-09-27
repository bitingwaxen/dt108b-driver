#!/bin/bash
set -euo pipefail
QUEUE="DT108B_Labels"
if [ "$(id -u)" -ne 0 ]; then exec sudo "$0" "$@"; fi
cancel -a "$QUEUE" 2>/dev/null || true
lpadmin -x "$QUEUE" 2>/dev/null || true
systemctl disable --now dt108b-worker.service 2>/dev/null || true
rm -f /etc/systemd/system/dt108b-worker.service
systemctl daemon-reload
rm -f /usr/lib/cups/backend/dt108b
rm -rf /usr/share/ppd/dt108b /opt/dt108b /etc/dt108b /var/spool/dt108b
rm -f /var/log/dt108b-worker.log
systemctl restart cups avahi-daemon 2>/dev/null || true
echo "DT108B driver removed. CUPS/Avahi/packages were left installed for other printers."
