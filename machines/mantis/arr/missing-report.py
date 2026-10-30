#!/usr/bin/env python3
"""Weekly Telegram report of monitored episodes and movies that are still missing.

Decluttarr's search_missing job keeps searching for these; this report lists
what those searches have not found, so it can be fixed by hand (another
release, another indexer, or unmonitor). Skips items already downloading and
episodes that aired in the last 3 days (RSS usually picks those up).

Reads SONARR_API_KEY, RADARR_API_KEY, TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
from /root/arr/.env. Run by /etc/cron.d/arr-missing-report.
"""
import json
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone

ENV = dict(line.strip().split("=", 1) for line in open("/root/arr/.env") if "=" in line and not line.startswith("#"))


def get(port, key, path):
    req = urllib.request.Request(f"http://localhost:{port}/api/v3/{path}")
    req.add_header("X-Api-Key", key)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def missing_episodes():
    key = ENV["SONARR_API_KEY"]
    queued = {q["episodeId"] for q in get(8989, key, "queue?pageSize=1000")["records"] if q.get("episodeId")}
    cutoff = datetime.now(timezone.utc) - timedelta(days=3)
    shows = defaultdict(list)
    for e in get(8989, key, "wanted/missing?pageSize=5000&monitored=true&includeSeries=true")["records"]:
        aired = e.get("airDateUtc")
        if e["id"] in queued or not aired or datetime.fromisoformat(aired.replace("Z", "+00:00")) > cutoff:
            continue
        shows[e["series"]["title"]].append(f'S{e["seasonNumber"]:02}E{e["episodeNumber"]:02}')
    return [f"{t}: {len(eps)} ({', '.join(sorted(eps)[:8])}{', …' if len(eps) > 8 else ''})"
            for t, eps in sorted(shows.items())]


def missing_movies():
    key = ENV["RADARR_API_KEY"]
    queued = {q["movieId"] for q in get(7878, key, "queue?pageSize=1000")["records"] if q.get("movieId")}
    return [f'{m["title"]} ({m["year"]})'
            for m in get(7878, key, "wanted/missing?pageSize=5000&monitored=true")["records"]
            if m["id"] not in queued and m.get("isAvailable")]


def main():
    shows, movies = missing_episodes(), missing_movies()
    if not shows and not movies:
        text = "Media library: nothing missing."
    else:
        text = "Media library: still missing after searching\n"
        if shows:
            text += "\nSeries\n" + "\n".join(f"- {s}" for s in shows) + "\n"
        if movies:
            text += "\nMovies\n" + "\n".join(f"- {m}" for m in movies) + "\n"
    data = urllib.parse.urlencode({"chat_id": ENV["TELEGRAM_CHAT_ID"], "text": text[:4000]}).encode()
    urllib.request.urlopen(f'https://api.telegram.org/bot{ENV["TELEGRAM_BOT_TOKEN"]}/sendMessage', data, timeout=30)


if __name__ == "__main__":
    main()
