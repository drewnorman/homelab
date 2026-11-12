#!/usr/bin/env python3
"""Read the TV's playback state through a forced-command SSH key."""

import json
import subprocess
import sys


def main(ssh, key, known_hosts):
    command = [
        ssh,
        "-F", "/dev/null",
        "-i", key,
        "-o", "IdentitiesOnly=yes",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=3",
        "-o", f"UserKnownHostsFile={known_hosts}",
        "-o", "StrictHostKeyChecking=yes",
        "root@192.168.1.117",
        "status",
    ]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=8, check=True
        )
        data = json.loads(result.stdout)
        app_id = data.get("appId", "")
        acbs = data.get("acbs") or []
        state = "other_app" if app_id != "youtube.leanback.v4" else "idle"
        if state == "idle" and acbs:
            state = acbs[0].get("playStateNow", "idle")
        if state not in {
            "playing", "paused", "starting", "stopped", "idle", "other_app"
        }:
            state = "unknown"
        print(json.dumps({"state": state, "app_id": app_id}))
    except (
        OSError,
        ValueError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ):
        print('{"state":"unavailable","app_id":""}')


if __name__ == "__main__":
    main(*sys.argv[1:4])
