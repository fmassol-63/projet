FROM postgres:15

RUN apt-get update && \
    apt-get install -y postgresql-15-repmgr && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/repmgr-entrypoint.sh
RUN chmod +x /usr/local/bin/repmgr-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
