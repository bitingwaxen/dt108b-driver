from __future__ import annotations

from pathlib import Path

import usb.backend.libusb1
import usb.core
import usb.util

from .constants import VID, PID, INTERFACE, OUT_ENDPOINT


LIBUSB_CANDIDATES = (
    Path("/opt/homebrew/opt/libusb/lib/libusb-1.0.dylib"),
    Path("/usr/local/opt/libusb/lib/libusb-1.0.dylib"),
    Path("/opt/homebrew/lib/libusb-1.0.dylib"),
    Path("/usr/local/lib/libusb-1.0.dylib"),
)


def find_libusb_backend():
    for candidate in LIBUSB_CANDIDATES:
        if not candidate.exists():
            continue
        backend = usb.backend.libusb1.get_backend(
            find_library=lambda _name, path=str(candidate): path
        )
        if backend is not None:
            return backend

    return usb.backend.libusb1.get_backend()


class USBPrinter:
    def __init__(self) -> None:
        self.device = None
        self.endpoint = None

    def open(self) -> "USBPrinter":
        try:
            backend = find_libusb_backend()
            self.device = usb.core.find(
                idVendor=VID,
                idProduct=PID,
                backend=backend,
            )
        except usb.core.NoBackendError as exc:
            raise RuntimeError(
                "libusb backend was not found. Install Homebrew libusb."
            ) from exc

        if self.device is None:
            raise RuntimeError(
                f"Printer not found: VID=0x{VID:04X}, PID=0x{PID:04X}"
            )

        try:
            self.device.set_configuration()
        except usb.core.USBError:
            pass

        configuration = self.device.get_active_configuration()
        interface = configuration[(INTERFACE, 0)]

        try:
            if self.device.is_kernel_driver_active(INTERFACE):
                self.device.detach_kernel_driver(INTERFACE)
        except (NotImplementedError, usb.core.USBError):
            pass

        usb.util.claim_interface(self.device, INTERFACE)

        self.endpoint = usb.util.find_descriptor(
            interface,
            bEndpointAddress=OUT_ENDPOINT,
        )

        if self.endpoint is None:
            self.close()
            raise RuntimeError("USB OUT endpoint 0x01 was not found.")

        return self

    def write_all(self, payload: bytes, progress_callback=None) -> int:
        if self.endpoint is None:
            raise RuntimeError("USB connection is not open.")

        total = 0
        size = len(payload)

        while total < size:
            end = min(total + 4096, size)
            written = self.endpoint.write(
                payload[total:end],
                timeout=20000,
            )

            if written is None or written <= 0:
                raise RuntimeError(
                    f"USB write stopped after {total:,} of {size:,} bytes."
                )

            total += written

            if progress_callback:
                progress_callback(total, size)

        return total

    def close(self) -> None:
        if self.device is None:
            return

        try:
            usb.util.release_interface(self.device, INTERFACE)
        except Exception:
            pass

        usb.util.dispose_resources(self.device)
        self.device = None
        self.endpoint = None

    def __enter__(self) -> "USBPrinter":
        return self.open()

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()
