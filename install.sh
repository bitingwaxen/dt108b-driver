#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/Library/Printers/DT108B"
BACKEND="/usr/libexec/cups/backend/dt108b"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
PPD="$PPD_DIR/DT108B.ppd"
QUEUE_NAME="DT108B_Direct"
SERVICE="com.pickybear.dt108b-worker"
PLIST="/Library/LaunchDaemons/$SERVICE.plist"
SOURCE_PLIST="$REPO_DIR/cups/$SERVICE.plist"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: This installer is for macOS."
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

REAL_USER="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
ARCH="$(uname -m)"

if [ "$ARCH" = "arm64" ]; then
  BREW="/opt/homebrew/bin/brew"
else
  BREW="/usr/local/bin/brew"
fi

if [ ! -x "$BREW" ]; then
  echo "ERROR: Native Homebrew was not found at $BREW"
  echo "Install Homebrew first, then run this installer again."
  exit 1
fi

HAD_PYTHON=0
HAD_LIBUSB=0
sudo -u "$REAL_USER" "$BREW" list --versions python@3.12 >/dev/null 2>&1 && HAD_PYTHON=1
sudo -u "$REAL_USER" "$BREW" list --versions libusb >/dev/null 2>&1 && HAD_LIBUSB=1

echo "[1/9] Installing native runtime dependencies..."
sudo -u "$REAL_USER" "$BREW" install python@3.12 libusb

PYTHON="$(sudo -u "$REAL_USER" "$BREW" --prefix python@3.12)/bin/python3.12"
test -x "$PYTHON" || {
  echo "ERROR: Homebrew Python 3.12 was not found at $PYTHON"
  exit 1
}

echo "[2/9] Removing older DT108B service and queue registrations..."
launchctl bootout "system/$SERVICE" 2>/dev/null || true
launchctl bootout system "$PLIST" 2>/dev/null || true
pkill -f '/Library/Printers/DT108B/dt108b_worker.py' 2>/dev/null || true
cancel -a "$QUEUE_NAME" 2>/dev/null || true
lpadmin -x "$QUEUE_NAME" 2>/dev/null || true
sleep 1

echo "[3/9] Installing isolated Python environment..."
rm -rf "$INSTALL_DIR"
install -d -o root -g wheel -m 755 "$INSTALL_DIR"

"$PYTHON" -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/python3" -m pip install --upgrade pip
"$INSTALL_DIR/venv/bin/python3" -m pip install "$REPO_DIR"

PYTHON_INSTALLED_BY_DT108B=$((1 - HAD_PYTHON))
LIBUSB_INSTALLED_BY_DT108B=$((1 - HAD_LIBUSB))
cat > "$INSTALL_DIR/install-state.env" <<STATE
BREW_PATH=$BREW
PYTHON_INSTALLED_BY_DT108B=$PYTHON_INSTALLED_BY_DT108B
LIBUSB_INSTALLED_BY_DT108B=$LIBUSB_INSTALLED_BY_DT108B
STATE
chown root:wheel "$INSTALL_DIR/install-state.env"
chmod 600 "$INSTALL_DIR/install-state.env"

echo "[4/9] Installing worker, backend, and PPD..."
install -o root -g wheel -m 555   "$REPO_DIR/cups/dt108b_worker.py"   "$INSTALL_DIR/dt108b_worker.py"

install -d -o root -g wheel -m 700 "$INSTALL_DIR/jobs/failed"

install -o root -g wheel -m 755   "$REPO_DIR/cups/dt108b"   "$BACKEND"

install -d -o root -g wheel -m 755 "$PPD_DIR"
install -o root -g wheel -m 444   "$REPO_DIR/cups/DT108B.ppd"   "$PPD"

xattr -c "$BACKEND" "$INSTALL_DIR/dt108b_worker.py" 2>/dev/null || true

echo "[5/9] Removing stale development spool files..."
rm -rf /Users/Shared/DT108BQueue
rm -rf /private/var/spool/cups/tmp/DT108BQueue
find /private/var/spool/cups/tmp -maxdepth 1 -type f   ( -name 'dt108b-*.pdf' -o -name '.dt108b-*.tmp' )   -delete 2>/dev/null || true
rm -f /usr/libexec/cups/filter/dt108b-passthrough

echo "[6/9] Installing and starting launchd worker..."
plutil -lint "$SOURCE_PLIST"
rm -f "$PLIST"
install -o root -g wheel -m 644 "$SOURCE_PLIST" "$PLIST"
xattr -c "$PLIST" 2>/dev/null || true
plutil -lint "$PLIST"

if ! launchctl bootstrap system "$PLIST"; then
  sleep 1
  if ! launchctl print "system/$SERVICE" >/dev/null 2>&1; then
    launchctl bootout "system/$SERVICE" 2>/dev/null || true
    launchctl bootout system "$PLIST" 2>/dev/null || true
    sleep 1
    launchctl bootstrap system "$PLIST"
  fi
fi

launchctl enable "system/$SERVICE"
launchctl kickstart -k "system/$SERVICE"

echo "[7/9] Creating CUPS virtual printer..."
lpadmin   -p "$QUEUE_NAME"   -E   -v 'dt108b:/direct'   -P "$PPD"

lpoptions -p "$QUEUE_NAME" -o PageSize=Label4x6
lpadmin -p "$QUEUE_NAME" -o printer-error-policy=retry-job
cupsenable "$QUEUE_NAME"
cupsaccept "$QUEUE_NAME"

echo "[8/9] Installing command-line tools..."
install -d -m 755 /usr/local/bin
ln -sf "$INSTALL_DIR/venv/bin/dt108b-print" /usr/local/bin/dt108b-print
ln -sf "$INSTALL_DIR/venv/bin/dt108b-diagnose" /usr/local/bin/dt108b-diagnose

echo "[9/9] Restarting CUPS and verifying installation..."
cupsctl --no-debug-logging 2>/dev/null || true
launchctl kickstart -k system/org.cups.cupsd 2>/dev/null ||   killall -HUP cupsd 2>/dev/null || true
sleep 2

launchctl print "system/$SERVICE" >/dev/null
lpstat -p "$QUEUE_NAME" -l
lpstat -v "$QUEUE_NAME"

echo
echo "Installation complete."
echo "Printer: DT108B Direct"
echo "CLI:     dt108b-print /path/to/label.pdf"
echo "Log:     /Library/Logs/DT108BWorker.log"
echo
echo "Chrome: select DT108B Direct and 4 x 6 in paper."
