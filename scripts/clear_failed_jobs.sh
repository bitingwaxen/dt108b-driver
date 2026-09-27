#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
rm -f /Library/Printers/DT108B/jobs/failed/dt108b-*.pdf
echo "Cleared failed DT108B job files."
