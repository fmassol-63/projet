FROM postgres:15

RUN apt-get update && \
    apt-get install -y postgresql-15-repmgr gosu && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint-primary.sh /usr/local/bin/entrypoint-primary.sh
COPY entrypoint-standby.sh /usr/local/bin/entrypoint-standby.sh
COPY entrypoint-witness.sh /usr/local/bin/entrypoint-witness.sh
RUN chmod +x /usr/local/bin/entrypoint-*.sh
