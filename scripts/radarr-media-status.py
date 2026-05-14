#!/usr/bin/env python3
import argparse
import json
import os
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


def parse_args():
    parser = argparse.ArgumentParser(
        description="Print Radarr movie status and optional media-folder matches."
    )
    parser.add_argument("term", nargs="?", help="Case-insensitive title/path search term.")
    parser.add_argument(
        "--config",
        default="/var/lib/radarr/config.xml",
        help="Radarr config.xml path. Defaults to the arr container path.",
    )
    parser.add_argument(
        "--url",
        default="http://localhost:7878",
        help="Radarr base URL. Defaults to http://localhost:7878.",
    )
    parser.add_argument(
        "--media-root",
        default="/mnt/media/media/movies",
        help="Movie media root to search when a term is provided.",
    )
    return parser.parse_args()


def load_api_key(config_path):
    return ET.parse(config_path).findtext("ApiKey")


def get_json(url, api_key, path):
    request = urllib.request.Request(
        urllib.parse.urljoin(url.rstrip("/") + "/", path.lstrip("/")),
        headers={"X-Api-Key": api_key},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def print_movie(movie):
    movie_file = movie.get("movieFile") or {}
    quality = ((movie_file.get("quality") or {}).get("quality") or {}).get("name")
    print(
        json.dumps(
            {
                "id": movie.get("id"),
                "title": movie.get("title"),
                "year": movie.get("year"),
                "tmdbId": movie.get("tmdbId"),
                "imdbId": movie.get("imdbId"),
                "hasFile": movie.get("hasFile"),
                "path": movie.get("path"),
                "movieFile": movie_file.get("relativePath"),
                "quality": quality,
                "size": movie_file.get("size"),
            },
            indent=2,
        )
    )


def print_filesystem_matches(media_root, term):
    if not os.path.isdir(media_root):
        print(f"\nMedia root does not exist: {media_root}")
        return

    normalized_term = term.lower()
    print("\nFilesystem matches:")
    found = False
    for dirpath, _dirnames, filenames in os.walk(media_root):
        relative_path = os.path.relpath(dirpath, media_root)
        if normalized_term not in relative_path.lower():
            continue

        found = True
        print(dirpath)
        for filename in sorted(filenames):
            path = os.path.join(dirpath, filename)
            print(f"  {os.path.getsize(path)} {filename}")

    if not found:
        print("No matching media folders.")


def main():
    args = parse_args()
    api_key = load_api_key(args.config)
    movies = get_json(args.url, api_key, "/api/v3/movie")
    missing = [movie for movie in movies if not movie.get("hasFile")]
    print(f"Radarr movies: {len(movies)} total, {len(missing)} missing")

    if args.term:
        normalized_term = args.term.lower()
        matches = [
            movie
            for movie in movies
            if normalized_term in (movie.get("title") or "").lower()
            or normalized_term in (movie.get("path") or "").lower()
        ]
        print(f"\nRadarr matches for {args.term!r}: {len(matches)}")
        for movie in matches:
            print_movie(movie)
        print_filesystem_matches(args.media_root, args.term)
    elif missing:
        print("\nMissing movies:")
        for movie in missing[:10]:
            print(f"{movie.get('title')} ({movie.get('year')}) at {movie.get('path')}")
        if len(missing) > 10:
            print(f"...and {len(missing) - 10} more missing")


if __name__ == "__main__":
    main()
