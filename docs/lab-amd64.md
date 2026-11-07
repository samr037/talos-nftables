# Reproduce the AMD64 Talos VM test on Proxmox

This lab boots the **published** `ghcr.io/samr037/talos-nftables:v0.1.1` extension in Talos v1.13.3. The VM has 2 vCPU, 2 GiB RAM, and a sparse 10 GiB disk. QEMU user networking keeps it off the LAN; only the Talos API is forwarded to the Proxmox host's loopback address. It does not join an existing Kubernetes cluster.

The image build commands run on a machine with Docker, `talosctl`, Python 3, and `zstd`. Proxmox needs an active directory storage with about 10 GiB available and a free VM ID.

## Build and import the boot image

On the build machine:

```bash
./lab/build-amd64.sh
PVE=root@YOUR_PROXMOX_HOST
VMID=YOUR_FREE_VM_ID
STORAGE=YOUR_DIRECTORY_STORAGE

ssh "$PVE" 'mkdir -p /var/tmp/talos-nftables-amd64'
scp _out/amd64/asset/metal-amd64.raw.zst \
  "$PVE:/var/tmp/talos-nftables-amd64/metal-amd64.raw.zst"
ssh "$PVE" 'zstd -d -f /var/tmp/talos-nftables-amd64/metal-amd64.raw.zst -o /var/tmp/talos-nftables-amd64/metal-amd64.raw'
```

Create the VM. The custom QEMU network device uses its own DHCP and `10.0.2.15` guest address; it does not use a Proxmox bridge.

```bash
ssh "$PVE" "qm create $VMID --name talos-nft-amd64-lab --memory 2048 --balloon 0 --cores 2 --cpu host --machine q35 --bios seabios --ostype l26 --onboot 0 --serial0 socket --vga serial0 --args '-netdev user,id=labnet,hostfwd=tcp:127.0.0.1:15000-:50000 -device virtio-net-pci,netdev=labnet'"
ssh "$PVE" "qm set $VMID --rng0 source=/dev/urandom"
ssh "$PVE" "qm importdisk $VMID /var/tmp/talos-nftables-amd64/metal-amd64.raw $STORAGE --format qcow2"
ssh "$PVE" "qm set $VMID --virtio0 $STORAGE:$VMID/vm-$VMID-disk-0.qcow2 --boot order=virtio0"
ssh "$PVE" "qm resize $VMID virtio0 10G"
ssh "$PVE" "qm start $VMID"
```

The image contains a BIOS boot partition, so SeaBIOS works here. The VirtIO disk appears as `/dev/vda`, which the generated lab machine config uses. The VirtIO RNG supplies boot entropy.

## Check the policy

In a separate terminal, forward the API to the build machine:

```bash
PVE=root@YOUR_PROXMOX_HOST
ssh -N -L 127.0.0.1:15001:127.0.0.1:15000 "$PVE"
```

Then run the same packet assertion as the Apple Silicon lab, pointed at the AMD64 guest:

```bash
LAB_OUT="$PWD/_out/amd64" \
TALOS_ENDPOINT=127.0.0.1:15001 \
DEBUG_PLATFORM=linux/amd64 \
DEBUG_TAG=talos-nft-debug:amd64 \
./lab/check.sh
```

Check the installed extension and reboot persistence:

```bash
talosctl get extensions -e 127.0.0.1:15001 -n 10.0.2.15 --talosconfig _out/amd64/config/talosconfig
talosctl reboot -e 127.0.0.1:15001 -n 10.0.2.15 --talosconfig _out/amd64/config/talosconfig
talosctl service ext-nft-rules -e 127.0.0.1:15001 -n 10.0.2.15 --talosconfig _out/amd64/config/talosconfig
```

The VM can be stopped with `talosctl shutdown` using the same endpoint and config. The imported Proxmox disk is independent of the temporary raw files in `/var/tmp/talos-nftables-amd64/`.

## Recorded result, 2026-11-07

Tested on pve2 as isolated VM 133. Talos reported extension `nft-rules` version `0.1.1`; `ext-nft-rules` reached `Running` and logged `applied ruleset`.

| Check | Observation |
| :--- | :--- |
| Packet path | Before probe: `counter packets 0 bytes 0 drop`. The 44-byte IPv4 TCP packet with IHL 6 changed it to `counter packets 1 bytes 44 drop`. |
| Reboot | Service returned to `Running`, logged a fresh apply, and restored `table inet talos_nftables_demo` with a reset counter. |
| Invalid update | An `ExtensionServiceConfig` with `ip hdrlength > nope` passed Talos YAML validation but failed `nft -c`; the old table remained in the kernel. |
| Recovery | Reapplying the valid config returned the service to `Running` and logged a successful apply. |

No Kubernetes bootstrap was needed for any check.
