#!/bin/bash
set -euo pipefail
PDF="${1:-}"
QUEUE="${DT108B_QUEUE:-DT108B_Labels}"
if [ -z "$PDF" ] || [ ! -f "$PDF" ]; then echo "Usage: $0 /path/to/label.pdf"; exit 2; fi
echo "Submitting through CUPS queue: $QUEUE"
lp -d "$QUEUE" "$PDF"
sleep 5
echo; echo "=== Queue ==="; lpstat -p "$QUEUE" -l || true
echo; echo "=== Active jobs ==="; lpstat -o "$QUEUE" || true
echo; echo "=== Worker log ==="; sudo tail -30 /var/log/dt108b-worker.log || true
