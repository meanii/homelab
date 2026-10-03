# homelab repo context

`meanii/homelab` documents the machines I run and holds their configuration. It has two jobs:

1. A public project: readers see what runs where and how it fits together.
2. A rebuild kit: every setting made on a host is persisted here as a config file, template or script, so the setup can be reproduced.

Anything unrelated to these machines does not belong here.

## Machines

One folder per machine under `machines/<name>/`, one subfolder per stack. Each folder has a `readme.md` describing the current state and the rebuild steps.

| Name | Where | Role | Folder |
| --- | --- | --- | --- |
| mantis | Proxmox VE 9 at home, behind NAT | LXC containers: 100 immich, 101 vaultwarden, 102/104/106 Hermes agents, 103 adguard, 107 nginxproxymanager (NPM, frpc, tinyauth, cup), 109 beszel, 112 downly, 115 pocketid, 116 jellyfin, 117 arr (qBittorrent, Prowlarr, Sonarr, Radarr, Bazarr, Seerr), 118 tdarr. LAN 192.168.0.0/24, internal vmbr1 10.10.10.0/24 | `machines/mantis` |
| beetle | Hetzner VPS | Public entry point: Caddy, frps, NetBird, aliasvault, personal sites | `machines/beetle` |
| vultr | Vultr VPS | Tailscale peer relay, RustDesk server | `machines/vultr` |
| crab | this PC, Ubuntu 24.04, on 24x7 | 2 TB HDD `/mnt/data`: PBS datastore (Docker, `machines/crab/pbs`), NFS export `media` for CT 116-118 (1.2 TB project quota); Beszel agent, Ollama, Penpot | `machines/crab` |
| aws | AWS, temporary only | short-lived work; tear down after use, never commit state or credentials | none |

Ask the user for the machine name if a new host appears.

Domain: `aniicrite.dev` (Cloudflare). `*.ghost.aniicrite.dev` = from the internet via beetle and frp; `*.home.aniicrite.dev` = home network, straight to NPM. `meanii.dev` is not used; never add it to configs.

## Access from crab

Aliases in `~/.ssh/config` (key `~/.ssh/id_ed25519`): `ssh mantis`, `ssh beetle` (port 2269), `ssh vultr`. Addresses of the VPS machines and Tailscale IPs stay in `~/.ssh/config`, never in the repo. Read container files with `ssh mantis pct exec <id> -- cat <path>`.

Local secrets on crab (mode 600, never committed) in `~/.config/homelab/`: `telegram.env` (alert bot token and chat id), `pbs.env`, `jellyfin.env`, `arr.env` (qBittorrent password and arr API keys).

## Operating rules

- Persist every change: after changing a host, update the matching file here (copy the live config, replace secrets with placeholders) or add a script that reproduces the change. Secrets in scripts come from environment variables.
- Proxmox firewall is on (host and every CT, default drop). A new service port on a container needs a rule in `machines/mantis/proxmox/firewall/<id>.fw`.
- NPM proxy hosts: HTTP/2 off on every host (otherwise `421 Misdirected Request` through Caddy).
- Caddy on beetle is a custom build with the apt package on hold; do not `apt install caddy` or `caddy upgrade` without checking `caddy build-info`.
- frps and frpc are upgraded together.
- Backups: CT 100 (daily, `daily-immich`, including the photo library) and CT 101, 107, 115, 116, 117, 118 (weekly, `weekly-backup`, excluding `/scratch`) go to the Proxmox Backup Server on crab (storage `crab-pbs`); ask before adding others. The datastore is on crab's 2 TB HDD (`/mnt/data`), so there is no offsite copy; do not use crab's SK hynix NVMe. Docker on crab is rootless (container uid N = host uid 99999 + N).
- Media containers (116-118): media at `/data` is the NFS share from crab (bind mount `mp0`, hookscript `require-crab-media.sh`); apps run as uid/gid 1000 mapped to host 1000 via `lxc.idmap`. Temp, cache and download-in-progress files go under `/scratch` (not backed up). The GPU is passed as `/dev/dri/*`; images that drop root to an app user lose compose `group_add`, so CT 118 uses `mode=0666` on `renderD128`.
- Scripting APIs over SSH: do not pipe secrets into `python3 - <<EOF` (the heredoc is stdin); use a root-only temp file.

## What the docs must not contain

The repo is meant to be public. Beyond secrets (next section), keep these out of every file:

- security weaknesses, audit findings, lists of what is exposed or blocked, incident write-ups
- names of people (family members, friends) and personal or unrelated services running on the hosts
- Tailscale IPs and tailnet names, public IPs, account or project IDs, OAuth client IDs, Beszel or PocketID record IDs, bot usernames, chat IDs
- references to personal notes or other private repositories
- dated change logs; describe the current state and how to rebuild it

## Sensitive data: never commit or push

Real values stay on the hosts (gitignored `.env`, local config copies). Committed files use placeholders: `<VALUE>`, `${VAR}`, `{{ .Envs.VAR }}` (frp). Templates end in `.sample`, `.example` or `.template`.

Never commit:

- passwords, API keys, tokens, bot tokens, frp `auth.token`, Cloudflare API tokens, OAuth client secrets, restic repo passwords, bcrypt hashes
- public IP addresses of beetle, vultr, aws or the home WAN
- private keys, certificates, `.env` files, `kubeconfig`, AWS credentials, Terraform state or `*.tfvars`, `rclone.conf`, `acme.json`, service databases (`*.sqlite`, `*.db`)
- dumps, backups, or app data directories

## Push guard

1. `.gitignore` excludes secret-bearing file types.
2. `.githooks/pre-commit` runs `gitleaks git --pre-commit --staged` on staged changes.
3. `.githooks/pre-push` runs gitleaks on every commit being pushed; this also catches `--no-verify` commits.
4. `.github/workflows/secret-scan.yml` scans the full history on GitHub.

`.gitleaks.toml` extends the gitleaks defaults with `public-ipv4`, `literal-credential` and `sensitive-file`. `.gitleaksignore` lists reviewed findings in old commits only.

Setup per clone: gitleaks >= 8.30.1 on `PATH`, then `git config core.hooksPath .githooks` (set globally on crab). The hooks fail closed without gitleaks.

Agent rules:

- Never use `--no-verify` and never unset `core.hooksPath`.
- If a hook blocks, replace the value with a placeholder. Do not add findings to `.gitleaksignore` or weaken `.gitleaks.toml`. `# gitleaks:allow` only for confirmed false positives, with the user's approval.
- If a secret reaches GitHub: rotate it first, then rewrite history with the user's approval.
