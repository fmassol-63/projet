# Stack Zabbix HA + Vault Raft — ANSSI

## Architecture

| Host | IP | Conteneurs |
|---|---|---|
| HOST 1 | 192.168.200.170 | vault-1, vault-agent-1, postgresql, zabbix-server, zabbix-web |
| HOST 2 | 192.168.200.171 | vault-2, vault-agent-2, zabbix-server-2, zabbix-proxy, zabbix-agent |

## Sécurité ANSSI
- 5 clés de descellement / seuil 3
- Authentification AppRole (pas de token statique)
- Secrets injectés via Vault Agent sidecar

## Démarrage

### HOST 1
```bash
cd host1
docker compose up -d
# Desceller vault-1 (3/5 clés)
docker exec -it vault-1 vault operator unseal -address=http://127.0.0.1:8200
```

### HOST 2
```bash
cd host2
docker compose up -d
# Rejoindre le cluster Raft
docker exec -it vault-2 vault operator raft join http://192.168.200.170:8200
# Desceller vault-2 (3/5 clés)
docker exec -it vault-2 vault operator unseal -address=http://127.0.0.1:8200
```

## Accès
- Zabbix Web : http://192.168.200.170
- Vault UI : http://192.168.200.170:8200
