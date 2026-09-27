#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

for QUEUE in DT108B_Gap DT108B_Notch DT108B_Labels; do
  cancel -a "$QUEUE" 2>/dev/null || true
  lpadmin -x "$QUEUE" 2>/dev/null || true
done

systemctl disable --now dt108b-worker.service 2>/dev/null || true
rm -f /etc/systemd/system/dt108b-worker.service
systemctl daemon-reload

rm -f /usr/lib/cups/backend/dt108b
rm -rf /usr/share/ppd/dt108b
rm -rf /opt/dt108b
rm -rf /etc/dt108b
rm -rf /var/spool/dt108b
rm -f /var/log/dt108b-worker.log

systemctl restart cups avahi-daemon 2>/dev/null || true

echo "DT108B Linux driver removed."
echo "CUPS, Avahi, Python and system packages were left installed."
