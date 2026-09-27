#!/bin/bash
set -euo pipefail

MODE="${1:-}"
GAP="${2:-}"

if [ -z "$MODE" ]; then
  echo "Usage:"
  echo "  $0 gap 4"
  echo "  $0 notch 4"
  echo "  $0 continuous"
  echo "  $0 blackmark 4"
  exit 2
fi

case "$MODE" in
  gap)
    QUEUE="DT108B_Gap"
    PPD_MODE="Gap"
    ;;
  notch|hole)
    MODE="notch"
    QUEUE="DT108B_Notch"
    PPD_MODE="Notch"
    ;;
  continuous)
    QUEUE="DT108B_Gap"
    PPD_MODE="Continuous"
    ;;
  blackmark)
    QUEUE="DT108B_Gap"
    PPD_MODE="BlackMark"
    ;;
  *)
    echo "Unknown mode: $MODE"
    exit 2
    ;;
esac

sudo sed -i -E "s/^media_mode = .*/media_mode = $MODE/" /etc/dt108b/config.ini
sudo lpadmin -p "$QUEUE" -o "DTMediaMode=$PPD_MODE"

if [ "$MODE" != "continuous" ] && [ -n "$GAP" ]; then
  N="${GAP%mm}"
  sudo sed -i -E "s/^gap_mm = .*/gap_mm = $N/" /etc/dt108b/config.ini
  sudo lpadmin -p "$QUEUE" -o "DTGapSize=${N}mm"
fi

echo "Queue: $QUEUE"
lpoptions -p "$QUEUE"
