#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=${LAB_OUT:-"$root/_out/lab"}
config="$out/config/talosconfig"
debug_tar="$out/talos-nft-debug.tar"
endpoint=${TALOS_ENDPOINT:-127.0.0.1:15000}
node=${TALOS_NODE:-10.0.2.15}
debug_platform=${DEBUG_PLATFORM:-linux/arm64}
debug_tag=${DEBUG_TAG:-talos-nft-debug:lab}
test -f "$config" || { echo "Missing talosconfig: $config" >&2; exit 1; }

if ! test -f "$debug_tar"; then
  docker buildx build --platform "$debug_platform" --load \
    -f "$root/lab/Debug.Dockerfile" -t "$debug_tag" "$root"
  docker save "$debug_tag" -o "$debug_tar"
fi

talos() {
  talosctl "$@" -e "$endpoint" -n "$node" --talosconfig "$config"
}
talos service ext-nft-rules
talos logs ext-nft-rules
echo "Rules before probe:"
before_output=$(talos debug "$debug_tar" \
  --args /usr/sbin/nft,list,table,inet,talos_nftables_demo)
printf '%s\n' "$before_output"
before=$(printf '%s\n' "$before_output" | awk '/meta l4proto tcp ip hdrlength > 5/ { for (i=1; i<=NF; i++) if ($i == "packets") { print $(i+1); exit } }')
echo "Sending IPv4 TCP packet with IP options:"
talos debug "$debug_tar" \
  --args "/ip-options-probe,$node"
echo "Rules after probe (first counter should increase):"
after_output=$(talos debug "$debug_tar" \
  --args /usr/sbin/nft,list,table,inet,talos_nftables_demo)
printf '%s\n' "$after_output"
after=$(printf '%s\n' "$after_output" | awk '/meta l4proto tcp ip hdrlength > 5/ { for (i=1; i<=NF; i++) if ($i == "packets") { print $(i+1); exit } }')
if ! [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]] || (( after <= before )); then
  echo "FAIL: IPv4 options counter did not increase ($before -> $after)" >&2
  exit 1
fi
echo "PASS: IPv4 options counter increased ($before -> $after)"
