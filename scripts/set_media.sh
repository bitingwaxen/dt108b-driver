#!/bin/bash
set -euo pipefail
MODE="${1:-}"
GAP="${2:-}"
if [ -z "$MODE" ]; then
  echo "Usage: $0 gap 4 | notch 4 | continuous | blackmark 4"
  exit 2
fi
case "$MODE" in
  gap) PPD_MODE="Gap" ;;
  notch|hole) MODE="notch"; PPD_MODE="Notch" ;;
  continuous) PPD_MODE="Continuous" ;;
  blackmark) PPD_MODE="BlackMark" ;;
  *) echo "Unknown mode: $MODE"; exit 2 ;;
esac
sudo sed -i -E "s/^media_mode = .*/media_mode = $MODE/" /etc/dt108b/config.ini
sudo lpadmin -p DT108B_Labels -o "DTMediaMode=$PPD_MODE"
if [ "$MODE" != "continuous" ] && [ -n "$GAP" ]; then
  N="${GAP%mm}"
  sudo sed -i -E "s/^gap_mm = .*/gap_mm = $N/" /etc/dt108b/config.ini
  sudo lpadmin -p DT108B_Labels -o "DTGapSize=${N}mm"
fi
echo "Current CUPS defaults:"
lpoptions -p DT108B_Labels
echo; echo "Current driver config:"; cat /etc/dt108b/config.ini
