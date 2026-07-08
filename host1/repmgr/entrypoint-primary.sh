#!/bin/bash
set -e

# Laisse l'entrypoint standard Postgres faire l'init si volume vide
docker-entrypoint.sh postgres &
PG_PID=$!

# Attendre que Postgres soit prêt
until pg_isready -U "$POSTGRES_USER" -h 127.0.0.1; do
  sleep 2
done

# Créer rôle/DB repmgr si pas déjà fait
psql -U "$POSTGRES_USER" -d postgres -tc \
  "SELECT 1 FROM pg_roles WHERE rolname='repmgr'" | grep -q 1 || \
psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE ROLE repmgr LOGIN SUPERUSER PASSWORD '${REPMGR_PASSWORD}';"

psql -U "$POSTGRES_USER" -d postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname='repmgr'" | grep -q 1 || \
psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE DATABASE repmgr OWNER repmgr;"

# Enregistrer comme primaire si pas déjà membre du cluster
repmgr node check --role -f /etc/repmgr.conf 2>/dev/null || \
repmgr primary register -f /etc/repmgr.conf --force

# Lancer repmgrd en tâche de fond pour le monitoring/failover
repmgrd -f /etc/repmgr.conf --daemonize=false &

wait $PG_PID
