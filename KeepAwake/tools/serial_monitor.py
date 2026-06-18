"""Minimal serial monitor for ESP32-C3 USB-CDC.

Works headless, unlike `pio device monitor` (which needs a TTY and throws
termios errors when run in the background).

Usage:
    python serial_monitor.py <port> [seconds] [reset]

    <port>    serial device, e.g. /dev/cu.usbmodemXXXX (find via `pio device list`)
    seconds   how long to read, default 60
    reset     1 = pulse RTS to reset the chip and capture the boot log (default)
              0 = leave DTR/RTS alone, so an existing BLE connection stays up

Run with the Python that has pyserial; PlatformIO ships one, e.g.:
    ~/.platformio/penv/bin/python serial_monitor.py /dev/cu.usbmodemXXXX 30 0
"""

import sys
import time

import serial


def main():
    port = sys.argv[1]
    dur = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
    do_reset = (sys.argv[3] != "0") if len(sys.argv) > 3 else True

    s = serial.Serial(port, 115200, timeout=0.5)
    if do_reset:
        # On the classic auto-reset wiring DTR->GPIO9(boot), RTS->EN(reset):
        # keep GPIO9 high (normal boot) and pulse EN low to reset the chip.
        try:
            s.dtr = False
            s.rts = True
            time.sleep(0.2)
            s.rts = False
        except OSError as e:
            sys.stderr.write(f"reset toggle failed (continuing): {e}\n")

    end = time.time() + dur
    while time.time() < end:
        line = s.readline()
        if line:
            sys.stdout.write(line.decode("utf-8", "replace"))
            sys.stdout.flush()
    s.close()


if __name__ == "__main__":
    main()
