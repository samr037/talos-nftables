# Operations

## Inspect

```bash
talosctl -n NODE get extensions
talosctl -n NODE service ext-nft-rules
talosctl -n NODE logs ext-nft-rules
```

The service log prints `applied ruleset sha256=…` after a successful load. The hash is deliberately truncated in the log; it is for spotting changes, not for cryptographic verification. `talosctl get nftableschains` reports Talos-managed chain resources and does not enumerate arbitrary tables made by this extension. To inspect the kernel table, run `nft list table inet YOUR_TABLE` from a trusted Talos debug container with host network access; [lab/check.sh](../lab/check.sh) shows a reproducible debug image path.

## Change a rule

Edit the `content` of the node's `ExtensionServiceConfig`, then apply the complete machine configuration:

```bash
talosctl -n NODE apply-config --mode=try --file node.yaml
talosctl -n NODE logs ext-nft-rules
```

Talos v1.13.3 restarted the extension service when the config document changed in the lab. The loader also checks its file every five seconds. The batch re-creates the table contents, so its counters reset on a successful update.

## Invalid file

An nft syntax error appears in `talosctl logs ext-nft-rules` with the nft line and column. During an update, the last successfully installed kernel table remains active. Restore a valid config document and confirm a new `applied ruleset` log line. After a reboot with only an invalid file, no previous kernel rules exist: correct the file before relying on the mitigation.

## Remove the policy

Replace the rules file with an explicit `delete table inet YOUR_TABLE` batch, apply the config, and verify the table is gone before removing the extension. Simply deleting the `ExtensionServiceConfig` stops the service but does not remove rules already installed in the running kernel. A reboot clears those rules.

## Upgrade Talos

Build a new Talos installer image containing the extension for the target Talos version and architecture, then upgrade to that installer. Talos system extensions are activated during install or upgrade. Recheck `get extensions`, the service log, and the target table after reboot. Keep the extension image pinned by digest in the imager invocation for reproducible builds.
