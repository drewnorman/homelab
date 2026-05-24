FROM ghcr.io/open-webui/open-webui:main

COPY entrypoint.sh /entrypoint.sh
COPY seed.py /seed.py
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
