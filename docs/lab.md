# Reproduce the ARM64 Talos lab

The lab runs entirely on an Apple Silicon laptop. It does not connect to or modify a Proxmox cluster. QEMU user networking gives the guest `10.0.2.15`; host ports `15000` and `15123` forward to guest ports `50000` and `12345`.

For the separately tested AMD64 VM, see [the Proxmox lab guide](lab-amd64.md).

## Build and boot

```bash
./lab/build.sh
./lab/run.sh
```

The build script creates a loopback-only Docker registry, builds the extension, generates a fresh Talos machine config, and uses Talos imager v1.13.3 to create a disk image with both extension and config embedded. It converts that image to a sparse 10 GiB QCOW2 disk. All generated credentials and disks are ignored under `_out/lab/`. The lab adds `127.0.0.1` to its API certificate SAN only to support QEMU port forwarding.

The VM uses 2 vCPU and 2 GiB RAM. The `virtio-rng-pci` device matters: without it, Talos v1.13.3 stopped progressing immediately after `/sbin/init` on this Mac. QEMU's initial `Image type X64 can't be loaded` UEFI line was harmless; firmware continued to boot the ARM64 image.

## Check the exact match

In a second terminal:

```bash
./lab/check.sh
```

The check script builds a local debug image, imports it with `talosctl debug`, shows `table inet talos_nftables_demo`, sends a 44-byte IPv4 TCP SYN with four NOP IP option bytes, and shows the table again. The sample rule's `ip hdrlength > 5` counter should rise by one. The debug image and packet generator are lab tools only; the published extension image contains neither.

## Recorded result, 2026-11-06

| Exercise | Observation |
|---|---|
| Boot custom ISO | Talos initramfs enabled `nft-rules 0.1.0`. |
| Apply machine config | `ext-nft-rules` logged `applied ruleset`; independent debug container read its host nft table. |
| Reboot installed disk | Service Running; same table restored automatically. |
| Normal TCP packet to temporary port 12345 | Temporary drop counter increased from 0 to 1 (then to 7 due retransmission). |
| Crafted IPv4 TCP packet, IHL 6 | Sample rule counter increased from 0 to 1, 44 bytes. |
| Change to invalid nft syntax | `nft -c` failed; the previous table and counters remained in the kernel. |
| Restore example config | Service returned to Running; temporary port rule disappeared. |

The final VM config was restored to the example rule. The lab did not bootstrap Kubernetes, because the firewall is intended to work before Kubernetes is ready.

The generic example was rebuilt and checked again on 2026-11-06. The live `./lab/check.sh` output included:

```text
STATE    Running
meta l4proto tcp ip hdrlength > 5 counter packets 0 bytes 0 drop
sent 44-byte IPv4 TCP packet with IHL=6 to 10.0.2.15
meta l4proto tcp ip hdrlength > 5 counter packets 1 bytes 44 drop
PASS: IPv4 options counter increased (0 -> 1)
```
