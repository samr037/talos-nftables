# Design and safety

## Why an extension service

The rule loader is a Talos extension service because the intended use includes boot-time host mitigations. A Kubernetes DaemonSet with `hostNetwork: true` and `NET_ADMIN` is simpler when enforcement may wait for kubelet and the cluster API. Talos's native ingress firewall is the first choice for ordinary host port/subnet policy. [Talos extension services](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/extension-services) are explicitly for early system functions.

## Pieces

| Piece | Responsibility |
|---|---|
| OCI extension image | Supplies `/manifest.yaml`, the Talos service declaration, the Go loader, `nft`, and its dynamic libraries. |
| `ExtensionServiceConfig` | Supplies the desired native rules as a mounted file. The service has a `configuration: true` dependency. |
| Go loader | Reads the file, rejects an empty file, checks it with `nft -c`, applies the identical bytes with `nft -f`, and watches for changes. |
| Kernel nftables | Holds the actual rules and counters. A running loader is not in the packet path. |

The tested Talos v1.13.3 extension service ran in the host network namespace: a separate Talos debug container saw the table created by the loader and counted packets traversing the host's prerouting hook.

## Ownership and transactions

The sample begins with `table inet NAME {}`, `flush table inet NAME`, and a full definition of that same table. This is an idempotent nft batch: it creates the table if necessary, clears its existing contents, and installs the new definition. The loader never inserts `flush ruleset` on its own. Keep all objects belonging to one policy in tables reserved for this extension. Avoid Talos, CNI, kube-proxy, and other agents' tables.

`nft -c` catches syntax and kernel support errors before the actual batch. `nft -f` applies the batch transactionally. A failed update leaves the previous kernel ruleset in place, as observed in the VM lab. A bad file on a fresh boot has no prior table to preserve, so the mitigation is absent until corrected. The service logs the error and Talos restarts it.

This is a privileged administrator interface, not a sandbox for untrusted nft input. A malicious or mistaken rules file can change other tables or block the Talos API. Review rule scope and use Talos `apply-config --mode=try` when changing access rules. Keep an out-of-band console for recovery.

## Scope and ordering

The sample chain is `inet prerouting` at priority `raw`. An `accept` policy in this chain does not override a later drop in another chain. A `drop` takes effect when packets traverse this hook. CNI implementations using eBPF or hardware offload may handle some traffic before or outside this nft path; verify on the target node. Do not assume this host rule replaces Kubernetes NetworkPolicy.

The service waits for machine configuration and containerd. It does not wait for network connectivity or the Kubernetes API. That keeps the boot-time dependency chain short, but a very early packet can still arrive before the service has loaded its first rules. This extension does not provide a kernel-level guarantee of filtering from the first instruction of boot.
