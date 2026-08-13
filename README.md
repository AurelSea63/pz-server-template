<h1 align="center">🧟 Project Zomboid — Dockerized Dedicated Server (Build 42)</h1>

<p align="center">
  A <b>turnkey</b> template to deploy a <b>Project Zomboid Build 42</b> server with Docker Compose:<br>
  auto server download, Steam Workshop mods, secrets kept out of git, backups, live Discord notifications.
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/github/license/AurelSea63/pz-server-template?color=green">
  <img alt="Project Zomboid" src="https://img.shields.io/badge/Project%20Zomboid-Build%2042-red">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-Compose%20v2-2496ED?logo=docker&logoColor=white">
  <img alt="Bash" src="https://img.shields.io/badge/scripts-Bash-4EAA25?logo=gnubash&logoColor=white">
  <img alt="Stars" src="https://img.shields.io/github/stars/AurelSea63/pz-server-template?style=social">
</p>

> Built for a clean workflow: edit everything in the repo, the server only does `git pull` + reload.

### 🔔 Discord notifications preview

The watcher posts live to your channels (each one configurable):

> **🟢 Server started** — *#announcements*
> **👤 Player1 joined the server** — *#connections*
> **👤 Player2 left the server** — *#connections*
> **💀 Player1 died after surviving 2 days and 3 hours** — *#deaths*

## ✨ Features

- 🐳 **Docker**: self-built image (Ubuntu + PZ server via SteamCMD, bundled JRE)
- 🔧 **Workshop mods**: listed in the config, auto-downloaded on startup
- 🔐 **Secrets in `.env`** (never committed): admin / server / RCON passwords
- 🧟 **Versioned sandbox**: game settings live in the repo, applied on startup
- 💾 **Backups**: backup/restore script + rotation (cron-friendly)
- 🔔 **Discord** (optional): live notifications via webhooks (with survival time on death)
- 🛡️ **Security**: non-root container (privilege drop via `gosu`)

## 📋 Requirements

- Docker ≥ 20.10 and Docker Compose v2 (`docker compose`)
- ~6 GB free RAM, ~10 GB disk
- A Linux VPS/server (or Docker Desktop)

## 🚀 Quick start

```bash
git clone https://github.com/<you>/<repo>.git
cd <repo>

# 1) Secrets
cp .env.example .env
nano .env                 # set at least PZ_ADMIN_PASSWORD

# 2) Build (downloads the PZ server, ~5-10 min the first time)
docker compose build

# 3) Run
docker compose up -d
docker compose logs -f pz-server
```

Connect from the game: **Join → Add Server →** `YOUR_IP:16210`.

## ⚙️ Configuration

| File | Purpose |
|---|---|
| [`.env`](.env.example) | **Secrets** (passwords, Discord webhooks) — out of git |
| [`config/ServerTestServer.ini`](config/ServerTestServer.ini) | Server settings (name, ports, PVP, **mods**) |
| [`config/servertest_SandboxVars.lua`](config/servertest_SandboxVars.lua) | Sandbox settings (zombies, XP, loot…) |
| [`docker-compose.yml`](docker-compose.yml) | Resources, ports, volumes |

> ⚠️ **The game port is set with `DefaultPort`** in the ini (PZ ignores the `Port=` key).

After a config change: `docker compose restart pz-server`.
After an `.env` or ports change: **`docker compose up -d`** (recreates the container).

### Adding mods

In `config/ServerTestServer.ini`, fill **both** lists (same mods, same order):
```ini
WorkshopItems=2392709985;2857548524   # Workshop IDs (number in the URL)
Mods=tsarslib;ExampleMod              # internal IDs (Workshop page -> "Mod ID")
```
The server downloads the mods on the next startup. Recommended order: libraries → vehicles → QoL.

## 🔌 Ports & firewall

| Port | Proto | Role |
|---|---|---|
| 16210 | UDP (+TCP) | Game |
| 16211 | TCP/UDP | RCON / admin (**restrict to your IP**) |
| 8766-8767 | UDP | Steam Internet server list |
| 16262 | UDP | Direct connection port (perf) |

Open these ports in your host's firewall **and** locally (e.g. `ufw allow 16210/udp`).

### Public server (Steam list)
In the ini: `Public=true` + `PublicName=...`, open **8766-8767/udp**, wait ~2-5 min.

## 💾 Backups

```bash
sudo ./scripts/backup-world.sh backup        # manual (stops the server briefly)
sudo ./scripts/backup-world.sh auto-backup   # hot (for cron)
sudo ./scripts/backup-world.sh list
sudo ./scripts/backup-world.sh restore <name>
```
Cron every 3h (keeps the last 10):
```
0 */3 * * * /path/to/repo/scripts/backup-world.sh auto-backup >> /path/to/repo/backups/backup.log 2>&1
```

## 🛡️ Administration

`admin` account (password = `PZ_ADMIN_PASSWORD`), in-game admin panel, kick/ban, RCON…
→ see **[ADMIN-COMMANDS.md](ADMIN-COMMANDS.md)** (includes "wrong password" troubleshooting).

## 🔔 Discord (optional)

Set the webhooks in `.env`. Each event type can go to its own **dedicated channel**
(leave empty to disable; an empty webhook falls back to a default channel):

| Event | `.env` webhook | Content |
|---|---|---|
| 🟢 Start / 🔴 Stop | `DISCORD_ANNOUNCE_WEBHOOK` | — |
| 👤 Connect / disconnect | `DISCORD_CONNECT_WEBHOOK` | with the username |
| 💀 Death | `DISCORD_DEATH_WEBHOOK` (→ falls back to EVENT) | *"died after surviving 2 days and 3 hours"* |
| 🧟 Raid / horde | `DISCORD_EVENT_WEBHOOK` | — |
| 🔧 Admin / 💾 Backup | `DISCORD_WEBHOOK_URL` (general) | — |

**Real-time notifications** — the watcher continuously reads the logs and notifies automatically.
Deaths (with survival time) are read from `Zomboid/Logs/*_PerkLog.txt`, the rest from the container output:
```bash
# Manual test
sudo ./scripts/discord-watcher.sh

# As a service (recommended) — see systemd/pz-discord-watcher.service
sudo cp systemd/pz-discord-watcher.service /etc/systemd/system/
sudo sed -i "s#/path/to/repo#$(pwd)#g" /etc/systemd/system/pz-discord-watcher.service
sudo systemctl daemon-reload && sudo systemctl enable --now pz-discord-watcher
journalctl -u pz-discord-watcher -f
```
> Detection patterns are at the top of `discord-watcher.sh` — tweak them if an event doesn't
> fire (`docker logs pz-server` to see your version's exact format).

## 🔁 Recommended workflow

Edit config **in the repo** (commit/push), then on the server:
```bash
git pull && docker compose restart pz-server   # or 'up -d' if ports/env/volumes change
```
Secrets stay in the server's `.env` (out of git) → no conflict on `pull`.

## 🐛 Quick troubleshooting

- **Build doesn't download the game** → re-run `docker compose build` (SteamCMD retry included).
- **Nobody can connect** → check `DefaultPort` = mapped port, and the firewall (UDP!).
- **"wrong password"** → see [ADMIN-COMMANDS.md](ADMIN-COMMANDS.md) (often the client's favorites cache).
- **Mods block startup** → a mod incompatible with B42; remove it from `Mods=`/`WorkshopItems=`.

## 📄 License

MIT — do whatever you want. Contributions welcome.

---

*Project Zomboid is a trademark of The Indie Stone. This project is not affiliated.*
