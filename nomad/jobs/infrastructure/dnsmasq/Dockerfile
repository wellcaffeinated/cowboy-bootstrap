# Build iPXE binaries for multiple architectures
FROM docker.io/library/alpine:3.22.2 AS ipxe_build

# Pin iPXE version for reproducibility
ARG IPXE_REV=be3a78ea

WORKDIR /ipxe

# Install build dependencies and build iPXE for x86/x86_64
RUN apk update && \
    apk add git build-base perl xz-dev && \
    git clone https://github.com/ipxe/ipxe.git . && \
    git checkout ${IPXE_REV} && \
    cd src && \
    make bin/undionly.kpxe bin-x86_64-efi/snponly.efi

# Final image with dnsmasq and iPXE binaries
FROM alpine:3.22.2

WORKDIR /tftproot

# Install dnsmasq and tini (init system)
RUN apk add --no-cache dnsmasq tini

# Copy dnsmasq configuration
COPY dnsmasq.conf /etc/dnsmasq.conf

# Copy iPXE binaries from build stage
COPY --from=ipxe_build /ipxe/src/bin/undionly.kpxe .
COPY --from=ipxe_build /ipxe/src/bin-x86_64-efi/snponly.efi .

ENTRYPOINT ["/sbin/tini", "/usr/sbin/dnsmasq", "--no-daemon", "-C", "/etc/dnsmasq.conf"]
