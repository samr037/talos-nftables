#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/_out/lab"
talos_version=${TALOS_VERSION:-v1.13.3}
registry=talos-nft-lab-registry
network=talos-nft-lab
mkdir -p "$out/config" "$out/asset"

if ! docker network inspect "$network" >/dev/null 2>&1; then
  docker network create "$network" >/dev/null
fi
if ! docker inspect "$registry" >/dev/null 2>&1; then
  docker run -d --name "$registry" --network "$network" \
    -p 127.0.0.1:5005:5000 registry:2 >/dev/null
else
  docker start "$registry" >/dev/null
  docker network connect "$network" "$registry" 2>/dev/null || true
fi

docker buildx build --platform linux/arm64 --load \
  -t localhost:5005/talos-nftables:lab "$root"
docker push localhost:5005/talos-nftables:lab

talosctl gen config nft-lab https://10.0.2.15:6443 \
  --talos-version "$talos_version" --output-dir "$out/config" --force
python3 "$root/lab/prepare-config.py" \
  "$out/config/controlplane.yaml" \
  "$root/examples/extension-service-config.yaml" \
  "$out/config/lab-controlplane.yaml"
talosctl validate --config "$out/config/lab-controlplane.yaml" --mode metal

docker run --rm --network "$network" --privileged \
  -v "$out/asset:/out" \
  -v "$out/config/lab-controlplane.yaml:/config.yaml:ro" \
  "ghcr.io/siderolabs/imager:$talos_version" metal \
  --arch arm64 --insecure \
  --image-cache "ghcr.io/siderolabs/installer-base:$talos_version" \
  --system-extension-image "$registry:5000/talos-nftables:lab" \
  --embedded-config-path /config.yaml > "$out/asset/imager.log" 2>&1

zstd -d -f "$out/asset/metal-arm64.raw.zst" \
  -o "$out/asset/metal-arm64.raw"
qemu-img convert -f raw -O qcow2 \
  "$out/asset/metal-arm64.raw" "$out/talos-lab.qcow2"
rm "$out/asset/metal-arm64.raw"
qemu-img resize "$out/talos-lab.qcow2" 10G
docker stop "$registry" >/dev/null
echo "Lab disk ready: $out/talos-lab.qcow2"
echo "Next: $root/lab/run.sh"
