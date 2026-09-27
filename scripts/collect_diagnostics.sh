#!/bin/bash
set -u

OUTPUT="${1:-$HOME/Desktop/dt108b-diagnostics.txt}"

{
  echo "DT108B diagnostics"
  date
  echo
  sw_vers 2>&1 || true
  uname -a 2>&1 || true
  echo
  file /Library/Printers/DT108B/venv/bin/python3 2>&1 || true
  echo
  /usr/local/bin/dt108b-diagnose 2>&1 || true
  echo
  lpstat -p DT108B_Direct -l 2>&1 || true
  lpstat -v DT108B_Direct 2>&1 || true
  lpstat -W all -o DT108B_Direct 2>&1 || true
  echo
  sudo launchctl print system/com.pickybear.dt108b-worker 2>&1 || true
  echo
  sudo tail -100 /Library/Logs/DT108BWorker.log 2>&1 || true
  sudo tail -100 /Library/Logs/DT108BWorker.stderr.log 2>&1 || true
  echo
  sudo find /private/var/spool/cups/tmp -maxdepth 1     \( -name 'dt108b-*' -o -name '.dt108b-*' \) -ls 2>&1 || true
} > "$OUTPUT"

echo "Saved: $OUTPUT"
