FROM alpine:3.22.2

RUN apk add --no-cache dnsmasq tini

COPY dnsmasq.conf /etc/dnsmasq.conf

ENTRYPOINT ["/sbin/tini", "/usr/sbin/dnsmasq", "--no-daemon", "-C", "/etc/dnsmasq.conf"]
