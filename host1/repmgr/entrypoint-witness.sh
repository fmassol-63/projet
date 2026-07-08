#!/bin/bash
set -e

docker-entrypoint.sh postgres &
PG_PID=$!

until pg_isready -h 127.0.0.1; do
  sleep 2
done

for i in $(seq 1 60); do
  pg_isready -h "$PRIMARY_HOST" -U repmgr && break
  sleep 5
done

repmgr node check --role -f /etc/repmgr.conf 2>/dev/null || \
repmgr witness register -f /etc/repmgr.conf -h "$PRIMARY_HOST" --force

repmgrd -f /etc/repmgr.conf --daemonize=false &

wait $PG_PID
