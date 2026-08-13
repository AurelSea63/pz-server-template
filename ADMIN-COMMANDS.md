# 🛡️ Admin commands

Reference for administering players and the server.

---

## Becoming admin

1. In game, log in with the **`admin`** account (password = `PZ_ADMIN_PASSWORD` from `.env`).
2. To promote your own character: while logged in as `admin`, type in chat:
   ```
   /setaccesslevel "YourName" admin
   ```
**Levels**: `admin` > `moderator` > `overseer` > `gm` > `observer` > `none`.

---

## 🖱️ Easiest: the in-game Admin panel

Logged in as admin, a **gear button** appears → panel to manage players, spawn items,
tweak Sandbox options live, etc. Faster than commands for one-off actions.

---

## 💬 Chat commands (prefix `/`)

### Players
| Command | Effect |
|---|---|
| `/players` | List connected players |
| `/kickuser "name" -r "reason"` | Kick |
| `/banuser "name" -r "reason"` | Ban (`-ip` to ban the IP) |
| `/unbanuser "name"` | Unban |
| `/setaccesslevel "name" moderator` | Change access level |
| `/servermsg "message"` | Broadcast a message |
| `/additem "name" "Base.Axe" 1` | Give an item |
| `/teleport "name1" "name2"` | Teleport |

### Server & events
| Command | Effect |
|---|---|
| `/save` | Save the world now |
| `/quit` | Save **and stop** |
| `/changeoption <option> <value>` | Change an option live |
| `/alarm` `/gunshot` `/chopper` | Noises that attract zombies |
| `/startrain` `/startstorm` `/thunder` | Weather |

> Names with spaces **in quotes**: `/kickuser "John Doe"`.

---

## 🔌 RCON console (remote, out of game)

Requires an RCON client (e.g. `mcrcon`):
```bash
mcrcon -H YOUR_IP -P 16211 -p "<PZ_RCON_PASSWORD>" "players"
mcrcon -H YOUR_IP -P 16211 -p "<PZ_RCON_PASSWORD>" 'servermsg "Restart in 5 min"'
```
RCON port **16211** (restrict to your IP in the firewall), password = `PZ_RCON_PASSWORD` from `.env`.

---

## 🔑 "Wrong password" troubleshooting

From most to least common:

1. **Client cache (favorites)** — the PZ launcher remembers the login per favorite server.
   → **Remove the server from favorites, then re-add it** to enter the correct password.

2. **Forgotten character password** — delete the account, it's recreated on login (character kept, tied to the name):
   ```bash
   docker compose stop pz-server
   docker run --rm --volumes-from pz-server alpine sh -c \
     "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /opt/pz-server/Zomboid/db/servertest.db \"DELETE FROM whitelist WHERE username='TheName';\""
   docker compose start pz-server
   ```

3. **`admin` password changed in `.env`** — in this order:
   ```bash
   nano .env                        # PZ_ADMIN_PASSWORD=...
   docker compose up -d             # REQUIRED (restart does NOT reload .env)
   docker compose stop pz-server
   docker run --rm --volumes-from pz-server alpine sh -c \
     "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /opt/pz-server/Zomboid/db/servertest.db \"DELETE FROM whitelist WHERE username='admin';\""
   docker compose start pz-server   # PZ recreates 'admin' with the new password
   ```

> ⚠️ **Golden rules**
> - After editing `.env` → **`docker compose up -d`** (never `restart`/`start`).
> - `-adminpassword` only sets the password at account **creation** → to change it, delete the account from `whitelist` then **restart**.
> - Delete an account **while the server is stopped** (otherwise PZ only recreates `admin` on the next boot).
> - Account ≠ character: deleting the account keeps the character (tied to the name in the save).

---

## 🚨 In case of griefing (public server)
1. `/players` to identify
2. `/banuser "name" -ip -r "grief"`
3. Restore a clean backup: `sudo ./scripts/backup-world.sh restore <name>`
