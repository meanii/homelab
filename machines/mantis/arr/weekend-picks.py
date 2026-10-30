#!/usr/bin/env python3
"""Friday weekend picks: add a few new, well-rated movies and documentaries to Radarr.

Candidates come from Seerr's TMDb discover (released in the last 6 months, 12
for documentaries), most popular first. A candidate is kept only if it is
rated MIN_RATING+ on IMDb (TMDb scores run high for new films), out on digital
or disc, and Radarr's interactive search finds a release the profile approves
with enough seeders (per pool); that release is grabbed right away.
Otherwise the movie is removed again and may come back next week. Skips movies
already in Radarr or its exclusions, requested/blocklisted/deleted in Seerr, or
picked before (SEEN). Picks are tagged `weekend-pick` in Radarr and listed on
Telegram.

Reads RADARR_API_KEY, TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID from
/root/arr/.env and Seerr's API key from its settings.json. Run by
/etc/cron.d/arr-weekend-picks. --dry-run only prints the candidates that pass
the metadata filters (no release search, nothing added, no Telegram).
"""
import json
import sys
import textwrap
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path

ENV = dict(line.strip().split("=", 1) for line in open("/root/arr/.env") if "=" in line and not line.startswith("#"))
SEERR_KEY = json.load(open("/root/arr/config/seerr/settings.json"))["main"]["apiKey"]
SEEN = Path("/root/arr/weekend-picks.seen")  # tmdb ids picked before, one per line
ROOT, PROFILE, TAG = "/data/library/movies", 7, "weekend-pick"  # 7 = HD Bluray + WEB, same as Seerr
MIN_FREE_GB, MAX_SEARCHES = 200, 8  # MAX_SEARCHES per pool, each takes ~5-50 s
MIN_RATING = 7  # IMDb, or TMDb when IMDb has none
TODAY = date.today()

# (heading, picks per week, min seeders, Seerr discover filters, TMDb genre ids to skip).
# Indexers already require 5 seeders, and Radarr ranks seeders only coarsely (4-31 tie),
# so ask for enough that the pick finishes before the weekend. Documentaries are seeded
# thinly: at 20, 7 of 8 failed on the first run.
POOLS = [
    ("Movies", 3, 20,
     dict(primaryReleaseDateGte=TODAY - timedelta(days=180), voteAverageGte=6.5, voteCountGte=150, withRuntimeGte=80),
     {99, 10751, 27, 10770}),  # Documentary (own pool), Family, Horror, TV Movie
    ("Documentaries", 2, 10,
     dict(genre=99, primaryReleaseDateGte=TODAY - timedelta(days=365), voteAverageGte=6.5, voteCountGte=30,
          withRuntimeGte=60, excludeKeywords=156205),  # 156205 = concert film
     set()),
]


def api(base, key, path, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{base}/{path}", data, method=method,
                                 headers={"X-Api-Key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        raw = r.read()
    return json.loads(raw) if raw else None


def radarr(path, body=None, method=None):
    return api("http://localhost:7878/api/v3", ENV["RADARR_API_KEY"], path, body, method)


def candidates(filters):
    for page in range(1, 4):
        query = urllib.parse.urlencode(filters | {"sortBy": "popularity.desc", "page": page})
        r = api("http://localhost:5055/api/v1", SEERR_KEY, f"discover/movies?{query}")
        yield from r["results"]
        if page >= r["totalPages"]:
            return


def released(m):
    """Out on digital or disc. Like Radarr, assume so 90 days after cinemas when TMDb has no such date."""
    dates = [d[:10] for d in (m.get("digitalRelease"), m.get("physicalRelease")) if d]
    if not dates and m.get("inCinemas"):
        dates = [str(date.fromisoformat(m["inCinemas"][:10]) + timedelta(days=90))]
    return bool(dates) and min(dates) <= str(TODAY)


def rating(m):
    for source in ("imdb", "tmdb"):
        if (m["ratings"].get(source) or {}).get("value"):
            return source, m["ratings"][source]["value"]
    return "tmdb", 0


def grab(m, tag, min_seeders):
    """Add m to Radarr and grab its best acceptable release; remove it again if that fails.

    Returns (grabbed, number of releases the search found). The movie is added
    unmonitored so RSS sync and decluttarr's search_missing can't grab it while
    the interactive search runs; it is monitored once a release is grabbed.
    """
    movie = radarr("movie", m | {"qualityProfileId": PROFILE, "rootFolderPath": ROOT, "monitored": False,
                                 "minimumAvailability": "released", "tags": [tag],
                                 "addOptions": {"monitor": "movieOnly", "searchForMovie": False}})
    try:
        # Title matching needs the alternative titles the add's RefreshMovie saves.
        for _ in range(30):
            time.sleep(2)
            if not any(c["name"] == "RefreshMovie" and c["status"] in ("queued", "started") for c in radarr("command")):
                break
        releases = radarr(f"release?movieId={movie['id']}")  # best first, in Radarr's own order
    except urllib.error.HTTPError:
        releases = []
    for r in [r for r in releases if r["approved"] and (r.get("seeders") or 0) >= min_seeders][:3]:
        try:
            radarr("release", {"guid": r["guid"], "indexerId": r["indexerId"]})
        except urllib.error.HTTPError:  # e.g. 409 when the indexer link is dead: try the next release
            continue
        radarr("movie/editor", {"movieIds": [movie["id"]], "monitored": True}, method="PUT")
        return True, len(releases)
    radarr(f"movie/{movie['id']}?deleteFiles=false&addImportExclusion=false", method="DELETE")
    return False, len(releases)


def describe(m):
    source, score = rating(m)
    hours, mins = divmod(m.get("runtime") or 0, 60)
    blurb = textwrap.shorten(m.get("overview") or "", 160, placeholder="…")
    return f'- {m["title"]} ({m["year"]}), {hours}h{mins:02}m, {source.upper() if source == "tmdb" else "IMDb"} {score}, {", ".join(m["genres"][:3])}\n  {blurb}'


def telegram(text):
    data = urllib.parse.urlencode({"chat_id": ENV["TELEGRAM_CHAT_ID"], "text": text[:4000]}).encode()
    urllib.request.urlopen(f'https://api.telegram.org/bot{ENV["TELEGRAM_BOT_TOKEN"]}/sendMessage', data, timeout=30)


def main(dry):
    free_gb = next(r["freeSpace"] for r in radarr("rootfolder") if r["path"] == ROOT) // 10**9
    if free_gb < MIN_FREE_GB:
        return f"Weekend picks skipped: only {free_gb} GB free in {ROOT}."
    skip = {m["tmdbId"] for m in radarr("movie")} | {e["tmdbId"] for e in radarr("exclusions")}
    skip |= {int(i) for i in SEEN.read_text().split()} if SEEN.exists() else set()
    tag = None
    sections, found = [], []  # found: release count of every search
    for heading, want, min_seeders, filters, skip_genres in POOLS:
        picks, searches = [], 0
        for c in candidates(filters):
            if len(picks) == want or searches == MAX_SEARCHES:
                break
            # Seerr status 1 (unknown) is a watchlist entry or withdrawn request, not a reason to skip.
            if c["id"] in skip or (c.get("mediaInfo") or {}).get("status", 1) != 1 or skip_genres & set(c["genreIds"]):
                continue
            skip.add(c["id"])
            try:
                m = radarr(f"movie/lookup/tmdb?tmdbId={c['id']}")
            except urllib.error.HTTPError:  # 500 when Radarr's metadata server can't find or reach it
                continue
            if rating(m)[1] < MIN_RATING or not released(m):
                continue
            if not dry:
                tag = tag or next((t["id"] for t in radarr("tag") if t["label"] == TAG), None) \
                    or radarr("tag", {"label": TAG})["id"]
                searches += 1
                grabbed, n = grab(m, tag, min_seeders)
                found.append(n)
                if not grabbed:
                    continue
                with SEEN.open("a") as f:
                    f.write(f"{m['tmdbId']}\n")
            picks.append(m)
        if picks:
            sections.append(f"{heading}\n" + "\n".join(describe(m) for m in picks))
    if not sections:
        if found and not any(found):
            return "Weekend picks: every release search came back empty. Are Prowlarr's indexers up?"
        return "Weekend picks: nothing new with a good release this week."
    return "Weekend picks, downloading now:\n\n" + "\n\n".join(sections)


if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    try:
        text = main(dry)
    except Exception as e:
        if not dry:
            telegram(f"Weekend picks failed: {e!r}")
        raise
    print(text)  # also kept in cron mail if Telegram is down
    if not dry:
        telegram(text)
