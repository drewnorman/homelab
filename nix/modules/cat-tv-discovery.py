#!/usr/bin/env python3
"""Find recent cat-friendly uploads without relying on YouTube's RSS feeds."""

import json
import re
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


CHANNELS = {
    "birder": "UC7wafFu5c8AO0YF5U7R7xFA",
    "handsome": "UCJLIwYrmwgwbTzgmB5yVc7Q",
    "paul": "UCPJXfmxMYAoH02CFudZxmgg",
}
FALLBACKS = {
    "birder": "ZSkNCbrGsgc",
    "handsome": "A5JcZT5p240",
    "paul": "Iaq44gkMRaU",
}
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
OUTDOOR_TITLE = re.compile(
    r"cat tv|for cats|birds|squirrels|chipmunks|wildlife", re.I
)
LONG_TITLE = re.compile(r"hour|\bhr\b|long|live|24/7", re.I)


def youtube_get(endpoint, params, key):
    query = urlencode({**params, "key": key})
    request = Request(
        f"https://www.googleapis.com/youtube/v3/{endpoint}?{query}",
        headers={"User-Agent": "homelab-cat-tv/1.0"},
    )
    with urlopen(request, timeout=10) as response:
        return json.load(response)


def videos_for_channel(items, require_long_title):
    latest = None
    selected = []
    titles = {}
    for item in items:
        details = item.get("contentDetails") or {}
        snippet = item.get("snippet") or {}
        video_id = details.get("videoId", "")
        title = snippet.get("title", "")
        if not VIDEO_ID.fullmatch(video_id) or title in {
            "Private video", "Deleted video"
        }:
            continue
        if latest is None:
            latest = video_id
            titles[video_id] = title
        if OUTDOOR_TITLE.search(title) and (
            not require_long_title or LONG_TITLE.search(title)
        ):
            if video_id not in selected:
                selected.append(video_id)
                titles[video_id] = title
        if len(selected) == 5:
            break
    return latest, selected, titles


def main(key_file):
    key = Path(key_file).read_text(encoding="utf-8").strip()
    if not key:
        raise ValueError("empty API key")

    channel_data = youtube_get(
        "channels",
        {"part": "contentDetails", "id": ",".join(CHANNELS.values())},
        key,
    )
    uploads = {
        item["id"]: item.get("contentDetails", {})
        .get("relatedPlaylists", {})
        .get("uploads")
        for item in channel_data.get("items", [])
    }

    result = {
        "latest": FALLBACKS["birder"],
        "titles": {
            FALLBACKS["birder"]: "Birder King fallback",
            FALLBACKS["handsome"]: "Handsome Nature fallback",
            FALLBACKS["paul"]: "Paul Dinning fallback",
        },
    }
    for name, channel_id in CHANNELS.items():
        playlist_id = uploads.get(channel_id)
        if not playlist_id:
            result[name] = [FALLBACKS[name]]
            continue
        try:
            playlist = youtube_get(
                "playlistItems",
                {
                    "part": "contentDetails,snippet",
                    "playlistId": playlist_id,
                    "maxResults": 15,
                },
                key,
            )
            latest, selected, titles = videos_for_channel(
                playlist.get("items", []), require_long_title=name != "birder"
            )
        except (OSError, ValueError, KeyError):
            latest, selected, titles = None, [], {}
        if name == "birder" and latest:
            result["latest"] = latest
        result["titles"].update(titles)
        result[name] = selected or [FALLBACKS[name]]

    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (IndexError, OSError, ValueError, KeyError):
        print("Cat TV discovery unavailable", file=sys.stderr)
        sys.exit(1)
