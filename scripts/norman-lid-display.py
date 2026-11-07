#!/usr/bin/python3
"""Show the Proxmox text console when the laptop lid is open."""

import os
import subprocess
from pathlib import Path
from time import sleep


FRAMEBUFFER_BLANK = Path("/sys/class/graphics/fb0/blank")
CONSOLE = Path("/dev/tty1")
LOGIN1 = [
    "org.freedesktop.login1",
    "/org/freedesktop/login1",
    "org.freedesktop.login1.Manager",
]
PROPERTY_MATCH = (
    "type=signal,path=/org/freedesktop/login1,"
    "interface=org.freedesktop.DBus.Properties,member=PropertiesChanged"
)


def disable_idle_blanking():
    # Otherwise consoleblank=60 turns the screen off even with the lid open.
    with CONSOLE.open("rb+", buffering=0) as console:
        subprocess.run(
            ["/usr/bin/setterm", "--blank=0", "--powerdown=0"],
            stdin=console,
            stdout=console,
            check=True,
            timeout=5,
            env={**os.environ, "TERM": "linux"},
        )
    print("console idle blanking disabled", flush=True)


def lid_is_closed():
    result = subprocess.check_output(
        ["/usr/bin/busctl", "--system", "get-property", *LOGIN1, "LidClosed"],
        text=True,
        timeout=5,
    ).strip()
    if result not in {"b true", "b false"}:
        raise ValueError(f"unexpected LidClosed property: {result}")
    return result == "b true"


def sync_display():
    closed = lid_is_closed()
    desired = 1 if closed else 0
    blank = int(FRAMEBUFFER_BLANK.read_text().strip())
    if blank != desired:
        FRAMEBUFFER_BLANK.write_text(f"{desired}\n")
    print(f"lid={'closed' if closed else 'open'}; framebuffer={'off' if closed else 'on'}", flush=True)


def main():
    while not FRAMEBUFFER_BLANK.exists():
        sleep(1)
    disable_idle_blanking()

    while True:
        # Subscribe before reading current state so a transition is not missed
        # between startup and the first D-Bus notification.
        with subprocess.Popen(
            [
                "/usr/bin/busctl",
                "--system",
                "--json=short",
                f"--match={PROPERTY_MATCH}",
                "monitor",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        ) as monitor:
            try:
                sync_display()
            except (OSError, subprocess.SubprocessError, ValueError) as error:
                print(f"initial lid state failed: {error}", flush=True)
            for line in monitor.stdout:
                if line.startswith("{"):
                    try:
                        sync_display()
                    except (OSError, subprocess.SubprocessError, ValueError) as error:
                        print(f"lid event failed: {error}", flush=True)
            print(f"D-Bus monitor exited: {monitor.wait()}", flush=True)
        sleep(2)


if __name__ == "__main__":
    main()
