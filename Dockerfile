FROM fedora:30

RUN dnf install jq certbot -y && dnf clean all
RUN mkdir -p /etc/letsencrypt

COPY secret-patch-template.json /
COPY deployment-patch-template.json /
COPY entrypoint.sh /

ENV DEST=secret

CMD ["/entrypoint.sh"]