#!/bin/bash
set -euo pipefail

echo "=== CUPS queues ==="
for queue in DT108B_Gap DT108B_Notch; do
  lpstat -p "$queue" -l || true
  lpstat -v "$queue" || true
done

echo
echo "=== AirPrint subtype ==="
avahi-browse -rt _universal._sub._ipp._tcp 2>/dev/null | grep -A12 -B2 -i DT108B || true

echo
echo "=== IPP ==="
avahi-browse -rt _ipp._tcp 2>/dev/null | grep -A12 -B2 -i DT108B || true
