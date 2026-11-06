FROM alpine:3.22 AS probe-build
RUN apk add --no-cache build-base
COPY lab/ip-options-probe.c /src/ip-options-probe.c
RUN cc -O2 -static -o /ip-options-probe /src/ip-options-probe.c

FROM alpine:3.22
RUN apk add --no-cache nftables
COPY --from=probe-build /ip-options-probe /ip-options-probe
ENTRYPOINT ["/usr/sbin/nft"]
