#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=${LAB_OUT:-"$root/_out/amd64"}
talos_version=${TALOS_VERSION:-v1.13.3}
extension_image=${EXTENSION_IMAGE:-ghcr.io/samr037/talos-nftables:v0.1.1}
mkdir -p "$out/config" "$out/asset"
out=$(cd "$out" && pwd)

talosctl gen config nft-amd64-lab https://10.0.2.15:6443 \
  --talos-version "$talos_version" --output-dir "$out/config" --force
python3 "$root/lab/prepare-config.py" \
  "$out/config/controlplane.yaml" \
  "$root/examples/extension-service-config.yaml" \
  "$out/config/lab-controlplane.yaml"
talosctl validate --config "$out/config/lab-controlplane.yaml" --mode metal

if ! docker run --rm --platform linux/amd64 --privileged \
  -v "$out/asset:/out" \
  -v "$out/config/lab-controlplane.yaml:/config.yaml:ro" \
  "ghcr.io/siderolabs/imager:$talos_version" metal \
  --arch amd64 --insecure \
  --image-cache "ghcr.io/siderolabs/installer-base:$talos_version" \
  --system-extension-image "$extension_image" \
  --embedded-config-path /config.yaml > "$out/asset/imager.log" 2>&1; then
  tail -n 40 "$out/asset/imager.log" >&2
  exit 1
fi

echo "AMD64 Talos image ready: $out/asset/metal-amd64.raw.zst"
echo "Extension image: $extension_image"
