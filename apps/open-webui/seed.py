#!/usr/bin/env python3
"""Seeds the Open WebUI knowledge base with homelab repo files on every cold start."""

import os
import sys

import requests

BASE_URL = "http://localhost:8080"
ADMIN_EMAIL = os.environ["WEBUI_ADMIN_EMAIL"]
ADMIN_PASSWORD = os.environ["WEBUI_ADMIN_PASSWORD"]
HOMELAB_REPO = os.environ.get("HOMELAB_REPO", "drewnorman/homelab")
COLLECTION_NAME = "Homelab Infrastructure"

# Files fetched from the master branch of HOMELAB_REPO and loaded into the
# knowledge collection. Add or remove paths here to adjust what Claude sees.
REPO_FILES = [
    "README.md",
    "variables.tf",
    "main.tf",
    "dns.tf",
    "tailscale.tf",
    "claude.tf",
    "ansible/inventory/group_vars/all.yml",
    "ansible/inventory/group_vars/proxmox.yml",
    "ansible/playbooks/site.yml",
]


def get_token() -> str:
    """Return a bearer token, signing up on the very first start."""
    r = requests.post(
        f"{BASE_URL}/api/v1/auths/signin",
        json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
    )
    if r.status_code == 200:
        return r.json()["token"]

    # No users exist yet — register the admin account.
    # Open WebUI always allows the first signup regardless of ENABLE_SIGNUP.
    r = requests.post(
        f"{BASE_URL}/api/v1/auths/signup",
        json={"name": "Admin", "email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
    )
    if r.status_code not in (200, 201):
        print(f"[seed] Auth failed ({r.status_code}): {r.text}", file=sys.stderr)
        sys.exit(1)
    return r.json()["token"]


def seed(token: str) -> None:
    headers = {"Authorization": f"Bearer {token}"}

    # Remove any existing collection so we start fresh with the latest repo content.
    existing = requests.get(f"{BASE_URL}/api/v1/knowledge/", headers=headers)
    existing.raise_for_status()
    for col in existing.json():
        if col.get("name") == COLLECTION_NAME:
            requests.delete(
                f"{BASE_URL}/api/v1/knowledge/{col['id']}/delete",
                headers=headers,
            )

    r = requests.post(
        f"{BASE_URL}/api/v1/knowledge/create",
        headers=headers,
        json={
            "name": COLLECTION_NAME,
            "description": f"Auto-seeded from {HOMELAB_REPO} on startup",
        },
    )
    r.raise_for_status()
    collection_id = r.json()["id"]

    for path in REPO_FILES:
        try:
            raw = requests.get(
                f"https://raw.githubusercontent.com/{HOMELAB_REPO}/master/{path}",
                timeout=10,
            )
            raw.raise_for_status()

            upload = requests.post(
                f"{BASE_URL}/api/v1/files/",
                headers=headers,
                files={"file": (os.path.basename(path), raw.content, "text/plain")},
            )
            upload.raise_for_status()

            requests.post(
                f"{BASE_URL}/api/v1/knowledge/{collection_id}/file/add",
                headers=headers,
                json={"file_id": upload.json()["id"]},
            ).raise_for_status()

            print(f"[seed]   + {path}")
        except Exception as exc:
            print(f"[seed]   - {path}: {exc}", file=sys.stderr)


if __name__ == "__main__":
    token = get_token()
    seed(token)
    print(f"[seed] Knowledge collection '{COLLECTION_NAME}' ready.")
