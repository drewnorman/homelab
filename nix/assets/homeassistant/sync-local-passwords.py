"""Keep existing Home Assistant local passwords aligned with LLDAP secrets.

This runs while Home Assistant is stopped. Passwords are read from sops-nix
runtime files and passed to Home Assistant's auth script in process memory,
never as operating-system command-line arguments.
"""

import io
import runpy
import sys
from contextlib import redirect_stdout
from pathlib import Path

CONFIG_DIR = "/var/lib/hass"


def auth_command(*args: str) -> str:
    from homeassistant.scripts import auth

    output = io.StringIO()
    with redirect_stdout(output):
        auth.run(["--config", CONFIG_DIR, *args])
    return output.getvalue().strip()


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("expected Home Assistant launcher and two secret file paths")

    # The Nix-wrapped launcher registers Home Assistant and all of its Python
    # dependencies on sys.path. Use a different run name so it does not start HA.
    runpy.run_path(sys.argv[1], run_name="home_assistant_auth_setup")

    passwords = {}
    accounts = (("drew", Path(sys.argv[2])), ("angela", Path(sys.argv[3])))
    for username, path in accounts:
        password = path.read_text(encoding="utf-8").rstrip("\n")
        if not password:
            raise SystemExit(f"empty password secret for {username}")
        passwords[username] = password

    listing = auth_command("list")
    users = set(listing.split("\n\n", 1)[0].splitlines())
    missing = set(passwords) - users
    if missing:
        raise SystemExit(f"Home Assistant local accounts missing: {', '.join(sorted(missing))}")

    for username, password in passwords.items():
        if auth_command("change_password", username, password) != "Password changed":
            raise SystemExit(f"could not update Home Assistant password for {username}")
        if auth_command("validate", username, password) != "Auth valid":
            raise SystemExit(f"Home Assistant password validation failed for {username}")

    print("Home Assistant local passwords synchronized for drew and angela")


if __name__ == "__main__":
    main()
