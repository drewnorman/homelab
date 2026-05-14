#!/usr/bin/env python3
import argparse
import datetime
import json
import os
import secrets
import sqlite3
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


DEFAULT_RULES = {
    "Christmas": [
        "christmas",
        "christmas eve",
        "xmas",
        "santa",
        "santa claus",
        "north pole",
    ],
    "Halloween": [
        "halloween",
        "halloweentown",
        "trick or treat",
        "jack-o-lantern",
        "jack o lantern",
    ],
    "Holiday": [
        "christmas",
        "christmas eve",
        "xmas",
        "santa",
        "santa claus",
        "north pole",
        "halloween",
        "halloweentown",
        "trick or treat",
        "thanksgiving",
        "new year's",
        "new year",
        "holiday",
    ],
}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Add seasonal Jellyfin genres to matching movies."
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("JELLYFIN_URL", "http://localhost:8096"),
        help="Jellyfin base URL. Defaults to JELLYFIN_URL or localhost.",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("JELLYFIN_API_KEY"),
        help="Jellyfin API key. Defaults to JELLYFIN_API_KEY.",
    )
    parser.add_argument(
        "--db",
        default="/var/lib/jellyfin/data/jellyfin.db",
        help="Jellyfin DB path used to create/reuse a service API key.",
    )
    parser.add_argument(
        "--api-key-name",
        default="homelab holiday genre sync",
        help="Name for the managed Jellyfin API key.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply updates. Without this, only prints planned changes.",
    )
    parser.add_argument(
        "--rules",
        help="Optional JSON file mapping genre names to keyword lists.",
    )
    return parser.parse_args()


def load_rules(path):
    if not path:
        return DEFAULT_RULES

    with open(path, encoding="utf-8") as rules_file:
        rules = json.load(rules_file)

    if not isinstance(rules, dict):
        raise SystemExit("Rules file must contain a JSON object.")

    return {genre: list(keywords) for genre, keywords in rules.items()}


def clean_text(value):
    return " ".join(str(value or "").lower().replace("_", " ").replace(".", " ").split())


def get_or_create_api_key(db_path, name):
    if not os.path.exists(db_path):
        raise SystemExit(
            "No API key was provided and the Jellyfin DB was not found. "
            "Set JELLYFIN_API_KEY or run this inside the Jellyfin container."
        )

    conn = sqlite3.connect(db_path)
    try:
        row = conn.execute(
            "select AccessToken from ApiKeys where Name = ? order by Id limit 1",
            (name,),
        ).fetchone()
        if row:
            return row[0]

        now = datetime.datetime.utcnow().isoformat()
        token = "homelab-" + secrets.token_hex(24)
        conn.execute(
            "insert into ApiKeys(DateCreated, DateLastActivity, Name, AccessToken) values(?, ?, ?, ?)",
            (now, now, name, token),
        )
        conn.commit()
        return token
    finally:
        conn.close()


def api_json(base_url, api_key, path, method="GET", body=None):
    data = None
    headers = {"X-Emby-Token": api_key}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        urllib.parse.urljoin(base_url.rstrip("/") + "/", path.lstrip("/")),
        data=data,
        headers=headers,
        method=method,
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode("utf-8")
        return json.loads(text) if text else None


def first_user_id(base_url, api_key):
    users = api_json(base_url, api_key, "/Users")
    admins = [user for user in users if (user.get("Policy") or {}).get("IsAdministrator")]
    user = admins[0] if admins else users[0]
    return user["Id"]


def movie_search_text(movie):
    fields = [
        movie.get("Name"),
        movie.get("OriginalTitle"),
        movie.get("Path"),
        " ".join(movie.get("Genres") or []),
        " ".join(movie.get("Tags") or []),
    ]
    return clean_text(" ".join(field for field in fields if field))


def matching_genres(movie, rules):
    text = movie_search_text(movie)
    matches = []
    for genre, keywords in rules.items():
        if any(clean_text(keyword) in text for keyword in keywords):
            matches.append(genre)
    return matches


def update_movie_genres(base_url, api_key, user_id, movie_id, added_genres):
    movie = api_json(base_url, api_key, f"/Users/{user_id}/Items/{movie_id}")
    current_genres = movie.get("Genres") or []
    for genre in added_genres:
        if genre not in current_genres:
            current_genres.append(genre)
    movie["Genres"] = current_genres
    api_json(base_url, api_key, f"/Items/{movie_id}", method="POST", body=movie)
    return current_genres


def main():
    args = parse_args()
    rules = load_rules(args.rules)
    api_key = args.api_key or get_or_create_api_key(args.db, args.api_key_name)
    user_id = first_user_id(args.url, api_key)

    movies_response = api_json(
        args.url,
        api_key,
        "/Users/{}/Items?{}".format(
            user_id,
            urllib.parse.urlencode(
                {
                    "Recursive": "true",
                    "IncludeItemTypes": "Movie",
                    "Fields": "Genres,Tags,Path",
                }
            ),
        ),
    )
    movies = movies_response.get("Items", [])
    planned = []

    for movie in movies:
        current_genres = movie.get("Genres") or []
        additions = [
            genre
            for genre in matching_genres(movie, rules)
            if genre not in current_genres
        ]
        if additions:
            planned.append((movie, additions))

    action = "Updating" if args.apply else "Would update"
    print(f"Jellyfin movies scanned: {len(movies)}")
    print(f"{action}: {len(planned)} movie(s)")

    for movie, additions in planned:
        label = "{} ({})".format(movie.get("Name"), movie.get("ProductionYear"))
        print(f"{label}: add {', '.join(additions)}")
        if args.apply:
            update_movie_genres(args.url, api_key, user_id, movie["Id"], additions)

    if not args.apply:
        print("Dry run only. Re-run with --apply to write changes.")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        sys.exit(f"Jellyfin API error: HTTP {error.code}: {error.read().decode('utf-8', errors='replace')}")
