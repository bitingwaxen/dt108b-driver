#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/label.pdf"
  exit 2
fi

FILE="$1"
test -f "$FILE" || { echo "File not found: $FILE"; exit 1; }

OUTPUT="$(lp -d DT108B_Direct "$FILE")"
echo "$OUTPUT"
JOB_ID="$(echo "$OUTPUT" | sed -n 's/.*-\([0-9][0-9]*\).*/\1/p')"
sleep 5

echo
lpstat -p DT108B_Direct -l || true
echo
lpstat -o DT108B_Direct || true
echo
sudo tail -30 /Library/Logs/DT108BWorker.log || true
echo
if [ -n "$JOB_ID" ]; then
  sudo grep -F "[Job $JOB_ID]" /var/log/cups/error_log | tail -50 || true
fi
