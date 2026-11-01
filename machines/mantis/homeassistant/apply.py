#!/usr/bin/env -S uv run --quiet --with websockets --with pyyaml python
"""Push dashboards/*.yaml and themes/homelab.yaml to Home Assistant (VM 120).

HA_TOKEN must hold a long-lived access token. Dashboards are saved over the
websocket API (no Core restart); the theme is copied over SSH and reloaded.
"""
import asyncio, json, os, pathlib, subprocess, sys, urllib.request
import websockets, yaml

HA = os.environ.get("HA_URL", "https://ha.home.aniicrite.dev")
tok = os.environ["HA_TOKEN"]
HERE = pathlib.Path(__file__).parent
SSH = "root@192.168.0.216"


async def save_dashboards():
    async with websockets.connect(HA.replace("http", "ws", 1) + "/api/websocket", max_size=None) as ws:
        await ws.recv()
        await ws.send(json.dumps({"access_token": tok, "type": "auth"}))
        assert json.loads(await ws.recv())["type"] == "auth_ok"
        for i, f in enumerate(sorted((HERE / "dashboards").glob("*.yaml")), start=1):
            cfg = yaml.safe_load(f.read_text())
            await ws.send(json.dumps({"id": i, "type": "lovelace/config/save",
                                      "url_path": f"dashboard-{f.stem}", "config": cfg}))
            r = json.loads(await ws.recv())
            print(f.name, "ok" if r.get("success") else r)


def push_theme():
    subprocess.run(["scp", "-q", str(HERE / "themes/homelab.yaml"), f"{SSH}:/config/themes/homelab.yaml"], check=True)
    req = urllib.request.Request(f"{HA}/api/services/frontend/reload_themes", method="POST", data=b"{}",
                                 headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()
    print("theme reloaded")


if __name__ == "__main__":
    what = sys.argv[1:] or ["theme", "dashboards"]
    if "theme" in what:
        push_theme()
    if "dashboards" in what:
        asyncio.run(save_dashboards())
