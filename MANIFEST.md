# Installation manifest

The installer creates only these persistent project artifacts:

- CUPS queue `DT108B_Direct` with URI `dt108b:/direct`
- `/Library/Printers/DT108B`
- `/Library/LaunchDaemons/com.pickybear.dt108b-worker.plist`
- `/usr/libexec/cups/backend/dt108b`
- `/Library/Printers/PPDs/Contents/Resources/DT108B.ppd`
- `/usr/local/bin/dt108b-print`
- `/usr/local/bin/dt108b-diagnose`
- `/Library/Logs/DT108BWorker.log*`
- transient `/private/var/spool/cups/tmp/dt108b-*.pdf` files

Homebrew dependencies are `python@3.12` and `libusb`. Their pre-install state
is recorded in `/Library/Printers/DT108B/install-state.env`.
