#!/bin/bash
while true; do
  RESULT=$(psql -U "$POSTGRES_USER" -h 127.0.0.1 -tAc "SELECT pg_is_in_recovery();" 2>/dev/null)
  if [ "$RESULT" = "f" ]; then
    RESPONSE="HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\nPRIMARY"
  else
    RESPONSE="HTTP/1.1 503 Service Unavailable\r\nContent-Length: 7\r\n\r\nSTANDBY"
  fi
  echo -e "$RESPONSE" | timeout 2 nc -l -p 8008 -q 1
done
