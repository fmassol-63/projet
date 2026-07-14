#!/bin/bash
set -e

docker-entrypoint.sh postgres &
PG_PID=$!

until pg_isready -U "$POSTGRES_USER" -h 127.0.0.1; do
  echo "En attente de Postgres..."
  sleep 2
done

psql -U "$POSTGRES_USER" -d postgres -tc \
  "SELECT 1 FROM pg_roles WHERE rolname='repmgr'" | grep -q 1 || \
psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE ROLE repmgr LOGIN SUPERUSER PASSWORD '${REPMGR_PASSWORD}';"

psql -U "$POSTGRES_USER" -d postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname='repmgr'" | grep -q 1 || \
psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE DATABASE repmgr OWNER repmgr;"

repmgr node check --role -f /etc/repmgr.conf 2>/dev/null || \
repmgr primary register -f /etc/repmgr.conf --force

repmgrd -f /etc/repmgr.conf --daemonize=false &

wait $PG_PID
