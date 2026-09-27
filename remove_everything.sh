#!/bin/bash
set -euo pipefail

REMOVE_BREW_DEPS=0
FORCE_BREW_DEPS=0
case "${1:-}" in
  "") ;;
  --remove-homebrew-deps)
    REMOVE_BREW_DEPS=1
    ;;
  --force-remove-homebrew-deps)
    REMOVE_BREW_DEPS=1
    FORCE_BREW_DEPS=1
    ;;
  *)
    echo "Usage: $0 [--remove-homebrew-deps|--force-remove-homebrew-deps]"
    exit 2
    ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: This script is for macOS."
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  if [ "$FORCE_BREW_DEPS" -eq 1 ]; then
    exec sudo "$0" --force-remove-homebrew-deps
  elif [ "$REMOVE_BREW_DEPS" -eq 1 ]; then
    exec sudo "$0" --remove-homebrew-deps
  else
    exec sudo "$0"
  fi
fi

SERVICE="com.pickybear.dt108b-worker"
INSTALL_DIR="/Library/Printers/DT108B"
STATE_FILE="$INSTALL_DIR/install-state.env"

BREW_PATH=""
PYTHON_INSTALLED_BY_DT108B=0
LIBUSB_INSTALLED_BY_DT108B=0

if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      BREW_PATH) BREW_PATH="$value" ;;
      PYTHON_INSTALLED_BY_DT108B) PYTHON_INSTALLED_BY_DT108B="$value" ;;
      LIBUSB_INSTALLED_BY_DT108B) LIBUSB_INSTALLED_BY_DT108B="$value" ;;
    esac
  done < "$STATE_FILE"
fi

echo "Removing all DT108B components..."

launchctl bootout "system/$SERVICE" 2>/dev/null || true
launchctl bootout system "/Library/LaunchDaemons/$SERVICE.plist" 2>/dev/null || true
pkill -f '/Library/Printers/DT108B/dt108b_worker.py' 2>/dev/null || true

{
  lpstat -v 2>/dev/null | sed -n 's/^device for \([^:]*\): dt108b:.*/\1/p'
  echo DT108B_Direct
} | sort -u | while IFS= read -r queue; do
  [ -n "$queue" ] || continue
  cancel -a "$queue" 2>/dev/null || true
  lpadmin -x "$queue" 2>/dev/null || true
done

rm -f "/Library/LaunchDaemons/$SERVICE.plist"
rm -f /Library/LaunchAgents/com.pickybear.dt108b*.plist
rm -f /usr/libexec/cups/backend/dt108b
rm -f /usr/libexec/cups/filter/dt108b-passthrough
rm -f "/Library/Printers/PPDs/Contents/Resources/DT108B.ppd"
rm -f "/Library/Printers/PPDs/Contents/Resources/DT108B.ppd.gz"
rm -f /private/etc/cups/ppd/DT108B_Direct.ppd*
rm -rf "$INSTALL_DIR"
rm -rf "/Applications/DT108B Label Printer.app"
rm -f /usr/local/bin/dt108b-print /usr/local/bin/dt108b-diagnose
rm -f /opt/homebrew/bin/dt108b-print /opt/homebrew/bin/dt108b-diagnose

rm -rf /Users/Shared/DT108BQueue
rm -rf /private/var/spool/cups/tmp/DT108BQueue
find /private/var/spool/cups/tmp -maxdepth 1 -type f   ( -name 'dt108b-*.pdf' -o -name '.dt108b-*.tmp' )   -delete 2>/dev/null || true

rm -f /Library/Logs/DT108BWorker.log*
rm -f /Library/Logs/DT108BWorker.stdout.log
rm -f /Library/Logs/DT108BWorker.stderr.log

for home in /Users/*; do
  [ -d "$home" ] || continue
  rm -rf "$home/Applications/DT108B Label Printer.app"
  rm -rf "$home/Library/Application Support/DT108B"
  rm -rf "$home/Library/Caches/com.pickybear.dt108b"*
  rm -f "$home/Library/Preferences/com.pickybear.dt108b"*.plist
  rm -f "$home/Library/LaunchAgents/com.pickybear.dt108b"*.plist
done

cupsctl --no-debug-logging 2>/dev/null || true
launchctl kickstart -k system/org.cups.cupsd 2>/dev/null ||   killall -HUP cupsd 2>/dev/null || true

if [ "$REMOVE_BREW_DEPS" -eq 1 ]; then
  if [ -z "$BREW_PATH" ]; then
    if [ -x /opt/homebrew/bin/brew ]; then
      BREW_PATH=/opt/homebrew/bin/brew
    elif [ -x /usr/local/bin/brew ]; then
      BREW_PATH=/usr/local/bin/brew
    fi
  fi

  if [ -n "$BREW_PATH" ] && [ -x "$BREW_PATH" ]; then
    CONSOLE_USER="$(stat -f '%Su' /dev/console)"
    for formula in python@3.12 libusb; do
      installed_by_driver=0
      case "$formula" in
        python@3.12) installed_by_driver="$PYTHON_INSTALLED_BY_DT108B" ;;
        libusb) installed_by_driver="$LIBUSB_INSTALLED_BY_DT108B" ;;
      esac

      if [ "$installed_by_driver" -ne 1 ] && [ "$FORCE_BREW_DEPS" -ne 1 ]; then
        echo "Leaving Homebrew $formula: it was not recorded as installed by this project."
        continue
      fi

      dependents="$(sudo -u "$CONSOLE_USER" "$BREW_PATH" uses --installed "$formula" 2>/dev/null || true)"
      if [ -n "$dependents" ]; then
        echo "Leaving Homebrew $formula because installed packages depend on it:"
        echo "$dependents"
      else
        sudo -u "$CONSOLE_USER" "$BREW_PATH" uninstall "$formula" || true
      fi
    done
  else
    echo "Homebrew was not found; no Homebrew dependencies were removed."
  fi
else
  echo
  echo "Homebrew python@3.12 and libusb were left in place because they may be shared."
  echo "The final installer can safely reuse them."
fi

echo
echo "Verification:"
if launchctl print "system/$SERVICE" >/dev/null 2>&1; then
  echo "  WARNING: launchd service is still registered."
else
  echo "  OK: launchd service removed"
fi

if lpstat -v 2>/dev/null | grep -q 'dt108b:'; then
  echo "  WARNING: a dt108b CUPS queue remains."
else
  echo "  OK: CUPS queue removed"
fi

for path in   /usr/libexec/cups/backend/dt108b   /Library/Printers/DT108B   /Library/LaunchDaemons/com.pickybear.dt108b-worker.plist   '/Library/Printers/PPDs/Contents/Resources/DT108B.ppd'; do
  if [ -e "$path" ]; then
    echo "  WARNING: still present: $path"
  else
    echo "  OK: removed: $path"
  fi
done

echo
echo "All DT108B project artifacts have been removed."
