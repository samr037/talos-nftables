#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/_out/lab"
disk="$out/talos-lab.qcow2"
firmware_dir=${QEMU_FIRMWARE_DIR:-/opt/homebrew/share/qemu}
test -f "$disk" || { echo "Run lab/build.sh first" >&2; exit 1; }
test -f "$firmware_dir/edk2-aarch64-code.fd" || {
  echo "Set QEMU_FIRMWARE_DIR to the directory containing edk2-aarch64-code.fd" >&2
  exit 1
}
if ! test -f "$out/edk2-vars.fd"; then
  cp "$firmware_dir/edk2-arm-vars.fd" "$out/edk2-vars.fd"
fi

exec qemu-system-aarch64 \
  -machine virt,accel=hvf -cpu host -smp 2 -m 2048 \
  -nographic -monitor none \
  -drive "if=pflash,format=raw,readonly=on,file=$firmware_dir/edk2-aarch64-code.fd" \
  -drive "if=pflash,format=raw,file=$out/edk2-vars.fd" \
  -drive "file=$disk,if=none,id=disk,format=qcow2" \
  -device virtio-blk-pci,drive=disk \
  -object rng-random,id=rng0,filename=/dev/urandom \
  -device virtio-rng-pci,rng=rng0 \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:15000-:50000,hostfwd=tcp:127.0.0.1:15123-:12345 \
  -device virtio-net-pci,netdev=net0
