#!/bin/bash
set -euo pipefail
echo "=== CUPS ==="
lpstat -p DT108B_Labels -l || true
lpstat -v DT108B_Labels || true
echo; echo "=== AirPrint subtype ==="
avahi-browse -rt _universal._sub._ipp._tcp 2>/dev/null | grep -A12 -B2 -i DT108B || true
echo; echo "=== IPP ==="
avahi-browse -rt _ipp._tcp 2>/dev/null | grep -A12 -B2 -i DT108B || true
