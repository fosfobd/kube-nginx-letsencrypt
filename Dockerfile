FROM fedora:30

RUN dnf install jq certbot -y && dnf clean all
RUN mkdir -p /etc/letsencrypt
RUN ln -s /usr/bin/python3 /usr/bin/python

COPY secret-patch-template.json /
COPY deployment-patch-template.json /
COPY entrypoint.sh /

ENV DEST=secret
ENV OVERWRITE=false

CMD ["/entrypoint.sh"]