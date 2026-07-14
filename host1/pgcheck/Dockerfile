FROM postgres:15
RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*
COPY checker.sh /usr/local/bin/checker.sh
RUN chmod +x /usr/local/bin/checker.sh
ENTRYPOINT ["/usr/local/bin/checker.sh"]
