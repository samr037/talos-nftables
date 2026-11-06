FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod ./
COPY cmd/ cmd/
COPY internal/ internal/
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags='-s -w' -o /nft-rules ./cmd/nft-rules

FROM alpine:3.22 AS nft
RUN apk add --no-cache nftables

FROM scratch
COPY extension/manifest.yaml /manifest.yaml
COPY extension/nft-rules.yaml /rootfs/usr/local/etc/containers/nft-rules.yaml
COPY --from=builder /nft-rules /rootfs/usr/local/lib/containers/nft-rules/nft-rules
COPY --from=nft /usr/sbin/nft /rootfs/usr/local/lib/containers/nft-rules/nft
COPY --from=nft /lib /rootfs/usr/local/lib/containers/nft-rules/lib
COPY --from=nft /usr/lib /rootfs/usr/local/lib/containers/nft-rules/usr/lib
