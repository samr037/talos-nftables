#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/_out/lab"
config="$out/config/talosconfig"
debug_tar="$out/talos-nft-debug.tar"
test -f "$config" || { echo "Run lab/build.sh first" >&2; exit 1; }

if ! test -f "$debug_tar"; then
  docker buildx build --platform linux/arm64 --load \
    -f "$root/lab/Debug.Dockerfile" -t talos-nft-debug:lab "$root"
  docker save talos-nft-debug:lab -o "$debug_tar"
fi

talos() {
  talosctl "$@" -e 127.0.0.1:15000 -n 10.0.2.15 --talosconfig "$config"
}
talos service ext-nft-rules
talos logs ext-nft-rules
echo "Rules before probe:"
before_output=$(talos debug "$debug_tar" \
  --args /usr/sbin/nft,list,table,inet,cve_2026_98432)
printf '%s\n' "$before_output"
before=$(printf '%s\n' "$before_output" | awk '/meta l4proto tcp ip hdrlength > 5/ { for (i=1; i<=NF; i++) if ($i == "packets") { print $(i+1); exit } }')
echo "Sending IPv4 TCP packet with IP options:"
talos debug "$debug_tar" \
  --args /ip-options-probe,10.0.2.15
echo "Rules after probe (first counter should increase):"
after_output=$(talos debug "$debug_tar" \
  --args /usr/sbin/nft,list,table,inet,cve_2026_98432)
printf '%s\n' "$after_output"
after=$(printf '%s\n' "$after_output" | awk '/meta l4proto tcp ip hdrlength > 5/ { for (i=1; i<=NF; i++) if ($i == "packets") { print $(i+1); exit } }')
if ! [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]] || (( after <= before )); then
  echo "FAIL: IPv4 options counter did not increase ($before -> $after)" >&2
  exit 1
fi
echo "PASS: IPv4 options counter increased ($before -> $after)"
