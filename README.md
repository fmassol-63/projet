# Infrastructure HA — Vault (Raft) + PostgreSQL (repmgr) + Zabbix

Documentation de l'architecture de haute disponibilité déployée sur 3 hôtes Docker, sans Kubernetes.

## Vue d'ensemble

| Hôte | IP | Rôle |
|---|---|---|
| Host 1 | 192.168.200.170 | Vault node 1 (voter) + Postgres **primaire** + Zabbix server/web |
| Host 2 | 192.168.200.171 | Vault node 2 (voter) + Postgres **standby** + Zabbix server (HA) |
| Host 3 | 192.168.200.172 | Vault node 3 (voter) + Postgres **witness** + HAProxy |

Deux briques de redondance indépendantes cohabitent sur les 3 mêmes hôtes :

1. **Vault** — cluster Raft à 3 nœuds (quorum réel, tolère la perte d'1 nœud).
2. **PostgreSQL** (base de Zabbix) — réplication streaming primaire/standby pilotée par `repmgr`, avec un 3ᵉ nœud témoin (`witness`) pour l'arbitrage, et un failover automatique via `repmgrd`.

Un **HAProxy** sur Host 3 fait office de point d'entrée unique pour Postgres, en routant le trafic vers le nœud qui est réellement primaire au moment T (health-check applicatif, pas juste "port ouvert").

---

## 1. Vault — Raft Integrated Storage

### Principe
Chaque nœud Vault stocke ses données localement (`/vault/data`) et les réplique via le protocole Raft directement entre les 3 conteneurs. Pas de backend externe, pas de Consul.

### Fichiers par hôte
```
hostX/
├── docker-compose.yml   → service vault-X
└── vault-X.hcl          → config Raft du nœud
```

### Config type (`vault-X.hcl`)
- `storage "raft"` avec `node_id` unique et `retry_join` vers les 2 autres nœuds.
- `listener "tcp"` sur le port 8200 (API) et cluster sur 8201.
- `tls_disable = 1` actuellement — **à activer en TLS si le réseau n'est pas totalement isolé**.

### Vérification du quorum
```bash
docker exec vault-1 vault operator raft list-peers
```
Doit afficher les 3 nœuds avec un `leader = true` sur l'un d'eux.

### Points d'attention
- **3 nœuds minimum** pour un vrai quorum (tolère 1 panne). Avec 2 nœuds seulement, pas de quorum possible en cas de perte d'un des deux.
- Chaque nœud doit être **descellé** (`vault operator unseal`) manuellement après un redémarrage, sauf mise en place d'un auto-unseal (KMS cloud, Transit Vault) — **non fait actuellement**, amélioration possible.
- Les `extra_hosts` de chaque `vault-X` doivent connaître les 2 autres nœuds par leur IP.

---

## 2. PostgreSQL (base Zabbix) — réplication + failover automatique via repmgr

### Architecture cluster repmgr

| Nœud | ID | Rôle | IP |
|---|---|---|---|
| zabbix-db | 1 | primary | 192.168.200.170 |
| zabbix-db-standby | 2 | standby | 192.168.200.171 |
| repmgr-witness | 3 | witness | 192.168.200.172 |

### Fichiers (structure identique sur les 3 hôtes)
```
hostX/repmgr/
├── Dockerfile              → image postgres:15 + repmgr + gosu
├── repmgr.conf             → config spécifique à chaque nœud (node_id, node_name, conninfo)
├── postgresql.conf         → host1 uniquement (wal_level, max_wal_senders, etc.)
├── pg_hba.conf             → host1 uniquement (règles d'accès réplication)
├── entrypoint-primary.sh   → utilisé sur host1
├── entrypoint-standby.sh   → utilisé sur host2
└── entrypoint-witness.sh   → utilisé sur host3
```

Les 3 scripts `entrypoint-*.sh` sont présents dans **chaque** dossier `repmgr/` (même image Docker buildée partout), seul le `entrypoint:` choisi dans le `docker-compose.yml` de chaque hôte diffère.

### Fonctionnement des entrypoints
- **`entrypoint-primary.sh`** (host1) : démarre Postgres normalement, crée le rôle/DB `repmgr` si absents, s'enregistre comme primaire (`repmgr primary register`), lance `repmgrd` en fond pour le monitoring/failover.
- **`entrypoint-standby.sh`** (host2) : si le volume de données est vide, clone le primaire via `repmgr standby clone` (avec retry tant que le primaire n'est pas joignable), puis démarre Postgres, s'enregistre comme standby, lance `repmgrd`.
- **`entrypoint-witness.sh`** (host3) : démarre un petit Postgres local, attend le primaire, s'enregistre comme témoin (`repmgr witness register`), lance `repmgrd`.

Tout est **automatique au démarrage du conteneur** — pas besoin d'exec manuel, compatible avec un déploiement GitOps (push → redéploiement automatique des stacks).

### Failover automatique
Chaque `repmgr.conf` (host1 et host2) contient :
```ini
failover=automatic
promote_command='repmgr standby promote -f /etc/repmgr.conf'
follow_command='repmgr standby follow -f /etc/repmgr.conf'
```
Le démon `repmgrd`, actif sur chaque nœud, surveille le cluster et déclenche la promotion automatique du standby si le primaire disparaît, **à condition que le quorum (2 nœuds sur 3, primaire+standby+witness) soit maintenu** — c'est le rôle du witness d'éviter le split-brain.

### Vérification du cluster
```bash
docker exec -it zabbix-db repmgr cluster show
```
Doit afficher les 3 nœuds : `zabbix-db (primary)`, `zabbix-db-standby (standby)`, `witness`.

### Ordre de démarrage à respecter
```bash
# 1. Host1 (primaire) en premier, attendre que le healthcheck soit "healthy"
docker compose up -d --build zabbix-db

# 2. Host2 (standby)
docker compose up -d --build zabbix-db-standby

# 3. Host3 (witness)
docker compose up -d --build repmgr-witness
```

### Variables d'environnement requises (`.env` identique sur les 3 hôtes)
```
POSTGRES_PASSWORD=xxx
REPMGR_PASSWORD=xxx
```

---

## 3. HAProxy — point d'entrée unique Postgres

### Pourquoi
Sans HAProxy, les applications (Zabbix) devraient savoir manuellement lequel des 2 Postgres est actuellement primaire après un failover. HAProxy automatise cette bascule.

### Principe
Un sidecar léger (`pg-check`) tourne à côté de chaque Postgres (host1 et host2) et répond sur le port `8008` :
- `200 OK` si le nœud est **primaire** (`pg_is_in_recovery() = false`)
- `503` si le nœud est **standby**

HAProxy (sur host3) interroge ce endpoint toutes les 3 secondes et route le trafic Postgres réel (port 5432) uniquement vers le nœud qui répond `200`.

### Fichiers
```
pg-check/
├── Dockerfile
└── checker.sh

haproxy/
└── haproxy.cfg
```

### Ports exposés sur Host 3
- `5433` → point d'entrée Postgres HAProxy (5432 déjà utilisé par le witness local)
- `7000` → dashboard de statut HAProxy (`http://192.168.200.172:7000/`)

### Configuration Zabbix à jour
Sur **host1** et **host2**, `zabbix-server` / `zabbix-server-2` / `zabbix-web` pointent désormais vers HAProxy et non plus directement vers un Postgres fixe :
```yaml
extra_hosts:
  - "zabbix-db:192.168.200.172"
environment:
  DB_SERVER_HOST: zabbix-db
  DB_SERVER_PORT: "5433"
```

---

## Résumé des SPOF résolus

| Avant | Après |
|---|---|
| Vault : cluster à 2 nœuds sans quorum réel | Vault : 3 nœuds Raft, tolère 1 panne |
| Postgres Zabbix : 1 seul conteneur, aucune redondance | Postgres : primaire + standby + witness, failover automatique |
| Zabbix pointait en dur sur l'IP du Postgres primaire | Zabbix passe par HAProxy, bascule transparente |

## Limites connues / améliorations possibles

- **Pas de TLS** entre les nœuds Vault (`tls_disable = 1`) — à activer si le réseau n'est pas totalement isolé.
- **Pas d'auto-unseal Vault** — un redémarrage de nœud nécessite un descellement manuel avec les clés.
- **`pg_hba.conf` en mode `trust`** — à passer en authentification par mot de passe (`scram-sha-256`) si le réseau 192.168.200.0/24 n'est pas parfaitement fiable/isolé.
- **HAProxy est lui-même un point unique** sur host3 — en cas de panne de host3, Vault perd son quorum ET l'accès Postgres est coupé. Une amélioration possible serait de dupliquer HAProxy (par ex. avec keepalived + VIP) sur un 4ᵉ point, mais cela dépasse le périmètre actuel à 3 hôtes.

## Commandes de diagnostic rapide

```bash
# État du cluster Vault
docker exec vault-1 vault operator raft list-peers

# État du cluster Postgres/repmgr
docker exec -it zabbix-db repmgr cluster show

# Statut HAProxy (primaire actif visible)
curl http://192.168.200.172:7000/
```
