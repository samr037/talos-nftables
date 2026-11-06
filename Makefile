IMAGE ?= ghcr.io/samr037/talos-nftables
VERSION ?= v0.1.1
TALOS_VERSION ?= v1.13.3

.PHONY: test build image-local image-push clean

test:
	go test ./...

build:
	mkdir -p _out
	CGO_ENABLED=0 GOOS=linux GOARCH=$$(go env GOARCH) go build -trimpath -ldflags='-s -w' -o _out/nft-rules ./cmd/nft-rules

image-local:
	docker buildx build --platform linux/arm64 --load -t $(IMAGE):$(VERSION) .

image-push:
	docker buildx build --platform linux/amd64,linux/arm64 --push -t $(IMAGE):$(VERSION) .

clean:
	rm -rf _out
