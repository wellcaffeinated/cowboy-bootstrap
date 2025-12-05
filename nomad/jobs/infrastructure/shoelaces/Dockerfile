FROM golang:alpine AS build

WORKDIR /shoelaces
RUN apk add --no-cache tini-static git && \
    git clone -b v1.2.0 https://github.com/thousandeyes/shoelaces.git . && \
    go mod vendor && \
    CGO_ENABLED=0 go build -o ./shoelaces . && \
    printf "---\nnetworkMaps:\n" > mappings.yaml

FROM alpine:3.22.2

RUN apk add --no-cache ca-certificates tzdata

# Copy shoelaces binary, web assets, tini
COPY --from=build /shoelaces/shoelaces /shoelaces
COPY --from=build /shoelaces/web /static
COPY --from=build /shoelaces/mappings.yaml /data/mappings.yaml
COPY --from=build /sbin/tini-static /tini

# Copy custom iPXE templates
COPY templates/*.ipxe.slc /data/ipxe/

EXPOSE 8081

ENTRYPOINT ["/tini", "/shoelaces", "-data-dir", "/data", "-static-dir", "/static"]
CMD []

