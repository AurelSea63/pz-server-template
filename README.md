# 🧟 Project Zomboid — Serveur dédié Docker (Build 42)

Template **clé en main** pour déployer un serveur **Project Zomboid Build 42** avec Docker Compose :
téléchargement auto du serveur, mods Steam Workshop, secrets hors git, sauvegardes, intégration Discord.

> Pensé pour un workflow propre : on édite tout dans le repo, le serveur ne fait que `git pull` + relance.

## ✨ Fonctionnalités

- 🐳 **Docker** : image auto-construite (Ubuntu + serveur PZ via SteamCMD, JRE embarqué)
- 🔧 **Mods Workshop** : listés dans la config, téléchargés automatiquement au démarrage
- 🔐 **Secrets dans `.env`** (jamais commités) : mots de passe admin / serveur / RCON
- 🧟 **Sandbox versionné** : réglages de jeu dans le repo, appliqués au démarrage
- 💾 **Sauvegardes** : script backup/restore + rotation (cron-friendly)
- 🔔 **Discord** (optionnel) : notifications via webhooks
- 🛡️ **Sécurité** : conteneur non-root (drop de privilèges via `gosu`)

## 📋 Prérequis

- Docker ≥ 20.10 et Docker Compose v2 (`docker compose`)
- ~6 Go de RAM libre, ~10 Go de disque
- Un VPS/serveur Linux (ou Docker Desktop)

## 🚀 Démarrage rapide

```bash
git clone https://github.com/<vous>/<repo>.git
cd <repo>

# 1) Secrets
cp .env.example .env
nano .env                 # définir au moins PZ_ADMIN_PASSWORD

# 2) Construire (télécharge le serveur PZ, ~5-10 min la 1re fois)
docker compose build

# 3) Lancer
docker compose up -d
docker compose logs -f pz-server
```

Connexion depuis le jeu : **Join → Add Server →** `VOTRE_IP:16210`.

## ⚙️ Configuration

| Fichier | Rôle |
|---|---|
| [`.env`](.env.example) | **Secrets** (mots de passe, webhooks Discord) — hors git |
| [`config/ServerTestServer.ini`](config/ServerTestServer.ini) | Réglages serveur (nom, ports, PVP, **mods**) |
| [`config/servertest_SandboxVars.lua`](config/servertest_SandboxVars.lua) | Réglages Sandbox (zombies, XP, loot…) |
| [`docker-compose.yml`](docker-compose.yml) | Ressources, ports, volumes |

> ⚠️ **Le port de jeu se règle avec `DefaultPort`** dans l'ini (la clé `Port=` est ignorée par PZ).

Après modification de la config : `docker compose restart pz-server`.
Après modification du `.env` ou des ports : **`docker compose up -d`** (recrée le conteneur).

### Ajouter des mods

Dans `config/ServerTestServer.ini`, renseignez les **deux** listes (mêmes mods, même ordre) :
```ini
WorkshopItems=2392709985;2857548524   # IDs Workshop (numéro dans l'URL)
Mods=tsarslib;ExampleMod              # IDs internes (page Workshop -> "Mod ID")
```
Le serveur télécharge les mods au prochain démarrage. Ordre conseillé : bibliothèques → véhicules → QoL.

## 🔌 Ports & pare-feu

| Port | Proto | Rôle |
|---|---|---|
| 16210 | UDP (+TCP) | Jeu |
| 16211 | TCP/UDP | RCON / admin (**restreindre à votre IP**) |
| 8766-8767 | UDP | Liste Steam Internet |
| 16262 | UDP | Port direct (perfs) |

Ouvrez ces ports dans le pare-feu de votre hébergeur **et** local (ex. `ufw allow 16210/udp`).

### Serveur public (liste Steam)
Dans l'ini : `Public=true` + `PublicName=...`, ouvrez **8766-8767/udp**, attendez ~2-5 min.

## 💾 Sauvegardes

```bash
sudo ./scripts/backup-world.sh backup        # manuel (coupe le serveur ~qq s)
sudo ./scripts/backup-world.sh auto-backup   # à chaud (pour cron)
sudo ./scripts/backup-world.sh list
sudo ./scripts/backup-world.sh restore <nom>
```
Cron toutes les 3 h (garde les 10 derniers) :
```
0 */3 * * * /chemin/vers/repo/scripts/backup-world.sh auto-backup >> /chemin/vers/repo/backups/backup.log 2>&1
```

## 🛡️ Administration

Compte `admin` (mot de passe = `PZ_ADMIN_PASSWORD`), panneau admin in-game, kick/ban, RCON…
→ voir **[ADMIN-COMMANDS.md](ADMIN-COMMANDS.md)** (inclut le dépannage « mot de passe erroné »).

## 🔔 Discord (optionnel)

Renseignez les webhooks dans `.env`. Chaque type d'event peut aller dans un **salon dédié**
(laissez vide pour désactiver ; un webhook vide retombe sur un salon de repli) :

| Event | Webhook `.env` | Contenu |
|---|---|---|
| 🟢 Démarrage / 🔴 Arrêt | `DISCORD_ANNOUNCE_WEBHOOK` | — |
| 👤 Connexion / déconnexion | `DISCORD_CONNECT_WEBHOOK` | avec le pseudo |
| 💀 Mort | `DISCORD_DEATH_WEBHOOK` (→ repli sur EVENT) | *« a survécu 2 jours et 3 heures »* |
| 🧟 Raid / horde | `DISCORD_EVENT_WEBHOOK` | — |
| 🔧 Admin / 💾 Backup | `DISCORD_WEBHOOK_URL` (général) | — |

**Notifications temps réel** — le watcher lit les logs en continu et notifie automatiquement.
Les morts (avec temps de survie) sont lues dans `Zomboid/Logs/*_PerkLog.txt`, le reste sur la sortie du conteneur :
```bash
# Test manuel
sudo ./scripts/discord-watcher.sh

# En service (recommandé) — voir systemd/pz-discord-watcher.service
sudo cp systemd/pz-discord-watcher.service /etc/systemd/system/
sudo sed -i "s#/path/to/repo#$(pwd)#g" /etc/systemd/system/pz-discord-watcher.service
sudo systemctl daemon-reload && sudo systemctl enable --now pz-discord-watcher
journalctl -u pz-discord-watcher -f
```
> Les patterns de détection sont en haut de `discord-watcher.sh` — ajustez-les si un event ne se
> déclenche pas (`docker logs pz-server` pour voir le format exact de votre version).

## 🔁 Workflow recommandé

Éditez la config **dans le repo** (commit/push), puis sur le serveur :
```bash
git pull && docker compose restart pz-server   # ou 'up -d' si ports/env/volumes changent
```
Les secrets restent dans le `.env` du serveur (hors git) → pas de conflit au `pull`.

## 🐛 Dépannage express

- **Le build ne télécharge pas le jeu** → relancez `docker compose build` (SteamCMD retry inclus).
- **Personne ne peut se connecter** → vérifiez `DefaultPort` = port mappé, et le pare-feu (UDP !).
- **« mot de passe erroné »** → voir [ADMIN-COMMANDS.md](ADMIN-COMMANDS.md) (souvent le cache des favoris du client).
- **Mods qui bloquent le démarrage** → un mod incompatible B42 ; retirez-le de `Mods=`/`WorkshopItems=`.

## 📄 Licence

MIT — faites-en ce que vous voulez. Contributions bienvenues.

---

*Project Zomboid est une marque de The Indie Stone. Ce projet n'est pas affilié.*
