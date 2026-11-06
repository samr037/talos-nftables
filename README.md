# talos-nftables

**Advanced nftables rules for the Talos host network, loaded before Kubernetes.**

Talos already has an [ingress firewall](https://docs.siderolabs.com/talos/v1.13/networking/ingress-firewall) for host ports and source subnets. This extension serves a narrower purpose: native nftables rules that need packet header matches, raw-priority hooks, sets, counters, or other expressions outside that interface.

```text
Talos machine config                  Talos boot image
└─ ExtensionServiceConfig             └─ nft-rules system extension
   └─ rules.nft                           ├─ ext-nft-rules service
                                         ├─ small Go rule loader
                                         └─ nft + libraries
                                                │
                                    check → atomic nft batch
                                                │
                                    host network namespace
```

## What it does

- Loads one administrator-supplied `.nft` file from `ExtensionServiceConfig.configFiles`.
- Runs `nft -c -f -` before `nft -f -`, using the same bytes for both commands.
- Applies changes when the file changes. Talos also restarts the extension service when its config document changes.
- Logs the first 8 bytes of the applied SHA-256 hash and nft diagnostics through `talosctl logs ext-nft-rules`.
- Runs as a Talos extension service, without depending on kubelet, the Kubernetes API, or CNI readiness.

The example owns only `table inet cve_2026_98432`. **Never put `flush ruleset` in a rules file**: this extension executes trusted administrator input with host firewall privileges. See [design and safety](docs/design.md).

## Quick lab on an Apple Silicon Mac

Requires Docker Desktop, QEMU, `talosctl`, `zstd`, Go, and Python 3. The lab builds a 2 GiB RAM / 2 vCPU Talos v1.13.3 ARM64 VM with a sparse 10 GiB disk. Docker uses a registry bound to `127.0.0.1:5005`; QEMU forwards the Talos API to `127.0.0.1:15000`.

```bash
./lab/build.sh
./lab/run.sh                 # leave this terminal running
```

In another terminal:

```bash
./lab/check.sh
```

`check.sh` prints the nftables table, sends one crafted IPv4 TCP packet with IP options inside the guest, and prints the table again. The `ip hdrlength > 5` counter should increase. The virtual RNG in `run.sh` is essential for Talos to finish booting in this QEMU setup. Generated machine credentials and disks stay in ignored `_out/`.

Full reproduction steps and the test record are in [the lab guide](docs/lab.md).

## Use on a Talos node

1. Build and publish the extension OCI image:

   ```bash
   make test
   make image-push IMAGE=ghcr.io/YOUR_USER/talos-nftables VERSION=v0.1.0
   ```

2. Use [Talos imager](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/boot-assets#imager) to include that image in a custom Talos installer or boot asset. The public Image Factory accepts official extensions only; it cannot add this custom one. System extensions take effect during Talos install or upgrade, not through a machine config edit alone.

3. Add [examples/extension-service-config.yaml](examples/extension-service-config.yaml) as an extra document in each target node's Talos machine configuration. Change the table name and rule body for your policy, then apply the machine config. The service waits for this document before starting.

4. Verify on the node:

   ```bash
   talosctl -n NODE get extensions
   talosctl -n NODE service ext-nft-rules
   talosctl -n NODE logs ext-nft-rules
   ```

For an exact installer build and rollout sequence, see [deployment](docs/deployment.md). For updating rules and recovering from errors, see [operations](docs/operations.md).

## The supplied rule

```nft
table inet cve_2026_98432 {}
flush table inet cve_2026_98432
table inet cve_2026_98432 {
  chain prerouting {
    type filter hook prerouting priority raw; policy accept;
    meta l4proto tcp ip hdrlength > 5 counter drop
  }
}
```

`ip hdrlength > 5` matches IPv4 headers with options. For TCP header options, the relevant field is `tcp doff`. `prerouting` can see traffic routed through the node as well as traffic to its host services; choose an additional interface, address, or port match if the mitigation should be narrower. See the [nftables field reference](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes).

## Project status

| Check | Result |
|---|---|
| Go unit tests and vet | Passed |
| ARM64 extension build | Passed |
| AMD64 extension build | Passed |
| Talos v1.13.3 ARM64 VM boot | Passed |
| Extension starts before Kubernetes readiness | Passed |
| Rules present after reboot | Passed |
| Crafted IPv4 TCP packet with IHL 6 | Matched and dropped; counter rose from 0 to 1 |
| Invalid nft syntax | Rejected; previous kernel table stayed active |
| AMD64 runtime VM | Not yet exercised |

## License

MIT. See [LICENSE](LICENSE).
