#!/bin/bash
set -e

DATA_DIR="/var/lib/postgresql/data"

if [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
  echo "Volume vide, clonage depuis le primaire..."

  for i in $(seq 1 60); do
    pg_isready -h "$PRIMARY_HOST" -U repmgr && break
    echo "Primaire pas encore prêt, retry ($i/60)..."
    sleep 5
  done

  gosu postgres repmgr standby clone \
    -f /etc/repmgr.conf \
    -h "$PRIMARY_HOST" -U repmgr -d repmgr \
    --fast-checkpoint -F
fi

docker-entrypoint.sh postgres &
PG_PID=$!

until pg_isready -h 127.0.0.1; do
  sleep 2
done

repmgr node check --role -f /etc/repmgr.conf 2>/dev/null || \
repmgr standby register -f /etc/repmgr.conf --force

repmgrd -f /etc/repmgr.conf --daemonize=false &

wait $PG_PID
