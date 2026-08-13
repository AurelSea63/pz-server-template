# 🛡️ Commandes d'administration

Référence pour administrer les joueurs et le serveur.

---

## Devenir admin

1. En jeu, connecte-toi avec le compte **`admin`** (mot de passe = `PZ_ADMIN_PASSWORD` du `.env`).
2. Pour promouvoir ton perso : connecté en `admin`, tape dans le chat :
   ```
   /setaccesslevel "TonPseudo" admin
   ```
**Niveaux** : `admin` > `moderator` > `overseer` > `gm` > `observer` > `none`.

---

## 🖱️ Le plus simple : le panneau Admin (in-game)

Connecté en admin, un **bouton roue crantée** apparaît → interface pour gérer joueurs, spawn d'items,
options Sandbox à chaud, etc. Plus rapide que les commandes pour le ponctuel.

---

## 💬 Commandes chat (préfixe `/`)

### Joueurs
| Commande | Effet |
|---|---|
| `/players` | Liste les joueurs connectés |
| `/kickuser "pseudo" -r "raison"` | Expulse |
| `/banuser "pseudo" -r "raison"` | Bannit (`-ip` pour l'IP) |
| `/unbanuser "pseudo"` | Débannit |
| `/setaccesslevel "pseudo" moderator` | Change le niveau d'accès |
| `/servermsg "message"` | Message diffusé |
| `/additem "pseudo" "Base.Axe" 1` | Donne un objet |
| `/teleport "pseudo1" "pseudo2"` | Téléportation |

### Serveur & events
| Commande | Effet |
|---|---|
| `/save` | Sauvegarde immédiate |
| `/quit` | Sauvegarde **et arrête** |
| `/changeoption <option> <valeur>` | Change une option à chaud |
| `/alarm` `/gunshot` `/chopper` | Bruits qui attirent les zombies |
| `/startrain` `/startstorm` `/thunder` | Météo |

> Les pseudos avec espace **entre guillemets** : `/kickuser "Jean Bon"`.

---

## 🔌 Console RCON (à distance, hors jeu)

Nécessite un client RCON (ex. `mcrcon`) :
```bash
mcrcon -H VOTRE_IP -P 16211 -p "<PZ_RCON_PASSWORD>" "players"
mcrcon -H VOTRE_IP -P 16211 -p "<PZ_RCON_PASSWORD>" 'servermsg "Redemarrage dans 5 min"'
```
Port RCON **16211** (à restreindre à votre IP dans le pare-feu), mot de passe = `PZ_RCON_PASSWORD` du `.env`.

---

## 🔑 Dépannage « mot de passe erroné »

Du plus fréquent au moins fréquent :

1. **Cache du client (favoris)** — le launcher PZ mémorise le login par serveur favori.
   → **Retire le serveur des favoris, puis rajoute-le** pour saisir le bon mot de passe.

2. **Compte perso oublié** — supprime-le, il se recrée au login (perso conservé, lié au pseudo) :
   ```bash
   docker compose stop pz-server
   docker run --rm --volumes-from pz-server alpine sh -c \
     "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /opt/pz-server/Zomboid/db/servertest.db \"DELETE FROM whitelist WHERE username='LePseudo';\""
   docker compose start pz-server
   ```

3. **Mot de passe `admin` changé dans `.env`** — dans cet ordre :
   ```bash
   nano .env                        # PZ_ADMIN_PASSWORD=...
   docker compose up -d             # OBLIGATOIRE (restart ne recharge PAS .env)
   docker compose stop pz-server
   docker run --rm --volumes-from pz-server alpine sh -c \
     "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /opt/pz-server/Zomboid/db/servertest.db \"DELETE FROM whitelist WHERE username='admin';\""
   docker compose start pz-server   # PZ recrée 'admin' avec le bon mot de passe
   ```

> ⚠️ **Règles d'or**
> - Après un `.env` modifié → **`docker compose up -d`** (jamais `restart`/`start`).
> - `-adminpassword` ne définit le mot de passe qu'à la **création** du compte → pour le changer, supprimer le compte de `whitelist` puis **redémarrer**.
> - Supprimer un compte **serveur arrêté** (sinon PZ ne le recrée qu'au prochain boot).
> - Compte ≠ personnage : supprimer le compte garde le perso (lié au pseudo dans la sauvegarde).

---

## 🚨 En cas de grief (serveur public)
1. `/players` pour identifier
2. `/banuser "pseudo" -ip -r "grief"`
3. Restaurer un backup propre : `sudo ./scripts/backup-world.sh restore <nom>`
