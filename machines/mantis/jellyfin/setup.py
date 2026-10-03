#!/usr/bin/env python3
# Configure Jellyfin through its API: startup wizard, API key, libraries,
# QSV encoding options and the nightly scan. Idempotent; safe to re-run.
#
# Runs on mantis (it reaches the container over vmbr1). Environment:
#   JELLYFIN_URL            base URL, default http://10.10.10.116:8096
#   JELLYFIN_ADMIN_PASSWORD admin password; required only when the startup
#                           wizard has not been completed yet
#   JELLYFIN_API_KEY        admin API key (app "homelab-setup"); created
#                           automatically when the wizard runs, otherwise
#                           required
import json
import os
import sys
import urllib.parse
import urllib.request

BASE = os.environ.get("JELLYFIN_URL", "http://10.10.10.116:8096")
SETUP_AUTH = 'MediaBrowser Client="setup", Device="crab", DeviceId="crab-setup-1", Version="1"'
KEY_APP = "homelab-setup"

LIBS = [
    ("Movies", "movies", "/data/library/movies"),
    ("Shows", "tvshows", "/data/library/tv"),
    ("Anime", "tvshows", "/data/library/anime"),
]
LIB_OPTS = {
    "PreferredMetadataLanguage": "en",
    "MetadataCountryCode": "IN",
    "EnableRealtimeMonitor": False,
}
# Scan Media Library task id; trigger daily at 03:00 local (ticks).
SCAN_TASK = "7738148ffcd07979c7ceb148e06b3aed"
SCAN_TRIGGER = [{"Type": "DailyTrigger", "TimeOfDayTicks": 108000000000}]


def call(method, path, query=None, body=None, auth=None):
    url = BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": auth} if auth else {}
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def auth_header(tok):
    parts = {"Client": "setup", "Device": "crab", "DeviceId": "crab-setup-1", "Version": "1"}
    parts["Token"] = tok
    return "MediaBrowser " + ", ".join(f'{k}="{v}"' for k, v in parts.items() if v)


status, public = call("GET", "/System/Info/Public")
print("version:", public["Version"], "wizard done:", public["StartupWizardCompleted"])

if not public["StartupWizardCompleted"]:
    # v12 creates the first user lazily: GET returns (and creates) it,
    # then POST renames it and sets the password.
    pw = os.environ["JELLYFIN_ADMIN_PASSWORD"]
    call("POST", "/Startup/Configuration", body={
        "UICulture": "en-US", "MetadataCountryCode": "IN",
        "PreferredMetadataLanguage": "en"})
    print("first user:", call("GET", "/Startup/User"))
    user_body = {"Name": "admin"}
    user_body["Password"] = pw
    print("set user:", call("POST", "/Startup/User", body=user_body)[0])
    print("complete:", call("POST", "/Startup/Complete")[0])
    status, result = call("POST", "/Users/AuthenticateByName",
                           body={"Username": "admin", "Pw": pw}, auth=SETUP_AUTH)
    session = result["AccessToken"]
    status, _ = call("POST", "/Auth/Keys", query={"app": KEY_APP},
                     auth=auth_header(session))
    assert status == 204, status
    print("api key created")

key = os.environ.get("JELLYFIN_API_KEY")
if not key:
    print("JELLYFIN_API_KEY is not set; cannot continue", file=sys.stderr)
    sys.exit(1)
auth = auth_header(key)

status, existing = call("GET", "/Library/VirtualFolders", auth=auth)
names = {v["Name"] for v in existing}
for name, ctype, path in LIBS:
    if name in names:
        print(f"skip library {name}: exists")
        continue
    status, _ = call("POST", "/Library/VirtualFolders",
                     query={"name": name, "collectionType": ctype,
                            "paths": path, "refreshLibrary": "false"},
                     body={"LibraryOptions": LIB_OPTS}, auth=auth)
    print(f"create library {name}: http={status}")

status, cfg = call("GET", "/System/Configuration/encoding", auth=auth)
cfg.update({
    "TranscodingTempPath": "/scratch/transcodes",
    "HardwareAccelerationType": "qsv",
    "QsvDevice": "/dev/dri/renderD128",
    "EnableTonemapping": True,
    "EnableVppTonemapping": True,
    "EnableThrottling": True,
    "EnableSegmentDeletion": True,
    "EnableHardwareEncoding": True,
    "AllowHevcEncoding": True,
    "AllowAv1Encoding": False,
    "EnableDecodingColorDepth10Hevc": True,
    "EnableDecodingColorDepth10Vp9": True,
    "EnableIntelLowPowerH264HwEncoder": False,
    "EnableIntelLowPowerHevcHwEncoder": False,
    "HardwareDecodingCodecs": ["h264", "hevc", "mpeg2video", "vc1", "vp8", "vp9"],
})
print("encoding update:", call("POST", "/System/Configuration/encoding",
                               body=cfg, auth=auth)[0])
print("scan trigger:", call("POST", f"/ScheduledTasks/{SCAN_TASK}/Triggers",
                            body=SCAN_TRIGGER, auth=auth)[0])
print("refresh:", call("POST", "/Library/Refresh", auth=auth)[0])
