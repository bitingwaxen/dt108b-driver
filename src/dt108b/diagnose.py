from __future__ import annotations

import usb.core
import usb.util

from .constants import VID, PID


def diagnose() -> str:
    try:
        device = usb.core.find(idVendor=VID, idProduct=PID)
    except usb.core.NoBackendError:
        return "libusb backend not found."

    if device is None:
        return (
            f"No printer found. Expected VID=0x{VID:04X}, PID=0x{PID:04X}."
        )

    def safe_string(index: int) -> str:
        if not index:
            return ""
        try:
            return usb.util.get_string(device, index) or ""
        except Exception as exc:
            return f"<unavailable: {exc}>"

    lines = [
        "DT108B-compatible printer found",
        f"VID:          0x{device.idVendor:04X}",
        f"PID:          0x{device.idProduct:04X}",
        f"Manufacturer: {safe_string(device.iManufacturer) or '<empty>'}",
        f"Product:      {safe_string(device.iProduct) or '<empty>'}",
        f"Serial:       {safe_string(device.iSerialNumber) or '<empty>'}",
    ]

    for configuration in device:
        for interface in configuration:
            lines.append(
                f"Interface {interface.bInterfaceNumber}: "
                f"class={interface.bInterfaceClass}, "
                f"subclass={interface.bInterfaceSubClass}, "
                f"protocol={interface.bInterfaceProtocol}"
            )

            for endpoint in interface:
                direction = (
                    "OUT"
                    if usb.util.endpoint_direction(endpoint.bEndpointAddress)
                    == usb.util.ENDPOINT_OUT
                    else "IN"
                )
                lines.append(
                    f"  Endpoint 0x{endpoint.bEndpointAddress:02X}: "
                    f"{direction}, max_packet={endpoint.wMaxPacketSize}"
                )

    return "\n".join(lines)
