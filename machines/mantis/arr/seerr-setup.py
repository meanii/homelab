#!/usr/bin/env python3
"""Configures Seerr (requests) in CT 117 through its API, idempotently.

Signs in with the Jellyfin admin (which also makes it the Seerr owner), enables the
Jellyfin libraries, adds Radarr and Sonarr (anime with its own root folder and
profile), turns on Telegram notifications and finishes the setup.

Run on crab:
  set -a; . ~/.config/homelab/jellyfin.env; . ~/.config/homelab/arr.env; \
    . ~/.config/homelab/telegram.env; set +a; python3 seerr-setup.py
"""
import http.cookiejar
import json
import os
import sys
import urllib.request

SEERR = os.environ.get("SEERR_URL", "http://192.168.0.209:5055") + "/api/v1"
JELLYFIN_HOST = "10.10.10.116"   # as seen from CT 117
ARR_HOST = {"radarr": "radarr", "sonarr": "sonarr"}  # compose service names (same Docker network)
PROFILES = {"radarr": "HD Bluray + WEB", "sonarr": "WEB-1080p", "anime": "[Anime] Remux-1080p"}

env = os.environ
jar = http.cookiejar.CookieJar()
web = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(SEERR + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with web.open(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:300]}")


# 1. Jellyfin sign-in. On a fresh install this also stores the Jellyfin server.
status = call("GET", "/settings/public")
login = dict(zip(("username", "password", "email"),
                 (env["JELLYFIN_ADMIN_USER"], env["JELLYFIN_ADMIN_PASSWORD"], "admin@local")))
if not status.get("initialized"):
    login |= {"hostname": JELLYFIN_HOST, "port": 8096, "useSsl": False, "urlBase": "", "serverType": 2}
call("POST", "/auth/jellyfin", login)
# 2. Libraries: sync from Jellyfin and enable all.
call("POST", "/settings/jellyfin/library/sync")
for lib in call("GET", "/settings/jellyfin/library"):
    if not lib.get("enabled"):
        call("PUT", f"/settings/jellyfin/library/{lib['id']}", {"enabled": True})


# 3. Radarr and Sonarr.
def arr(kind, port, key_var):
    base = dict(zip(("hostname", "port", "apiKey", "useSsl", "baseUrl"),
                    (ARR_HOST[kind], port, env[key_var], False, "")))
    info = call("POST", f"/settings/{kind}/test", base)
    prof = {p["name"]: p["id"] for p in info["profiles"]}
    roots = [r["path"] for r in info["rootFolders"]]
    cfg = base | {
        "name": kind.capitalize(), "is4k": False, "isDefault": True, "syncEnabled": True,
        "preventSearch": False, "externalUrl": f"https://{kind}.home.aniicrite.dev",
        "activeProfileId": prof[PROFILES[kind]], "activeProfileName": PROFILES[kind],
        "minimumAvailability": "released", "tags": [],
    }
    if kind == "radarr":
        cfg["activeDirectory"] = "/data/library/movies"
    else:
        cfg |= {"activeDirectory": "/data/library/tv", "seriesType": "standard",
                "activeAnimeProfileId": prof[PROFILES["anime"]],
                "activeAnimeProfileName": PROFILES["anime"],
                "activeAnimeDirectory": "/data/library/anime", "animeSeriesType": "anime",
                "activeLanguageProfileId": 1, "enableSeasonFolders": True, "animeTags": [],
                "monitorNewItems": "all"}
    missing = {cfg["activeDirectory"], cfg.get("activeAnimeDirectory", cfg["activeDirectory"])} - set(roots)
    if missing:
        sys.exit(f"{kind}: root folders {missing} not in {roots}")
    existing = call("GET", f"/settings/{kind}")
    if existing:
        call("PUT", f"/settings/{kind}/{existing[0]['id']}", cfg)
    else:
        call("POST", f"/settings/{kind}", cfg)


arr("radarr", 7878, "RADARR_API_KEY")
arr("sonarr", 8989, "SONARR_API_KEY")

# 4. Telegram: requests, approvals, availability and failures (bit flags from Seerr's Notification enum).
TYPES = 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024 | 2048 | 4096
call("POST", "/settings/notifications/telegram", {
    "enabled": True, "types": TYPES,
    "options": {"botAPI": env["TELEGRAM_BOT_TOKEN"], "chatId": env["TELEGRAM_CHAT_ID"],
                "sendSilently": False, "botUsername": ""}})
call("POST", "/settings/notifications/telegram/test", {
    "enabled": True, "types": TYPES,
    "options": {"botAPI": env["TELEGRAM_BOT_TOKEN"], "chatId": env["TELEGRAM_CHAT_ID"]}})

# 5. Finish the setup wizard.
call("POST", "/settings/initialize")
print(json.dumps({
    "initialized": call("GET", "/settings/public").get("initialized"),
    "libraries": [(l["name"], l["enabled"]) for l in call("GET", "/settings/jellyfin/library")],
    "radarr": [(s["name"], s["activeProfileName"], s["activeDirectory"]) for s in call("GET", "/settings/radarr")],
    "sonarr": [(s["name"], s["activeProfileName"], s["activeDirectory"], s.get("activeAnimeDirectory"))
               for s in call("GET", "/settings/sonarr")],
}, indent=1))
