#!/usr/bin/env python3
"""Admin tool: upload one episode video and register it in the database.

Usage:
  export SUPABASE_URL=https://xxxx.supabase.co
  export SUPABASE_SERVICE_ROLE_KEY=...        # SECRET. Never put this in the app.
  python tools/upload_episode.py --movie-id <uuid> --number 1 \
      --title "The Beginning" --file ./ep1.mp4

The movie itself (title, description, poster) is created once in the Supabase
dashboard: Table editor -> movies. Set published = true when ready.

Requires: pip install requests
"""
import argparse
import mimetypes
import os
import sys

import requests


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--movie-id", required=True)
    p.add_argument("--number", type=int, required=True, help="episode number, from 1")
    p.add_argument("--title", default="")
    p.add_argument("--duration", type=int, help="length in seconds (optional)")
    p.add_argument("--file", required=True)
    a = p.parse_args()

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        return 1
    url = url.rstrip("/")

    ext = os.path.splitext(a.file)[1] or ".mp4"
    path = f"{a.movie_id}/{a.number}{ext}"
    ctype = mimetypes.guess_type(a.file)[0] or "video/mp4"
    auth = {"Authorization": f"Bearer {key}", "apikey": key}

    print(f"Uploading {a.file} -> videos/{path}")
    with open(a.file, "rb") as f:
        r = requests.post(
            f"{url}/storage/v1/object/videos/{path}",
            headers={**auth, "Content-Type": ctype, "x-upsert": "true"},
            data=f,  # streamed, not loaded into memory
        )
    if not r.ok:
        print("Upload failed:", r.status_code, r.text, file=sys.stderr)
        return 1

    rest = {**auth, "Content-Type": "application/json",
            "Prefer": "return=representation,resolution=merge-duplicates"}

    ep = {"movie_id": a.movie_id, "episode_number": a.number, "title": a.title}
    if a.duration:
        ep["duration_seconds"] = a.duration
    r = requests.post(
        f"{url}/rest/v1/episodes?on_conflict=movie_id,episode_number",
        headers=rest, json=ep,
    )
    if not r.ok:
        print("Episode insert failed:", r.status_code, r.text, file=sys.stderr)
        return 1
    episode_id = r.json()[0]["id"]

    r = requests.post(
        f"{url}/rest/v1/episode_media?on_conflict=episode_id",
        headers=rest, json={"episode_id": episode_id, "video_path": path},
    )
    if not r.ok:
        print("Media insert failed:", r.status_code, r.text, file=sys.stderr)
        return 1

    print(f"Done. Episode {a.number} registered (id {episode_id}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
