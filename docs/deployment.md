# Build a Talos installer with this extension

Talos [activates system extensions during install or upgrade](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/system-extensions). The public Image Factory accepts official extensions only; use [Talos imager](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/boot-assets#imager) for this custom image.

The commands below target Talos v1.13.3 and AMD64. Use the matching imager and installer-base tags when changing Talos versions. This is a build recipe; verify the resulting installer on a lab node before a production rollout.

## 1. Publish the extension image

```bash
docker login ghcr.io
make test
make image-push IMAGE=ghcr.io/YOUR_USER/talos-nftables VERSION=v0.1.0
```

Make the GHCR package readable by the imager, or provide a GitHub token to the imager. Pin the image by digest once it is published.

## 2. Build an installer image

```bash
mkdir -p _out/installer
docker run --rm \
  -v "$PWD/_out/installer:/out" \
  ghcr.io/siderolabs/imager:v1.13.3 installer \
  --arch amd64 \
  --base-installer-image ghcr.io/siderolabs/installer-base:v1.13.3 \
  --system-extension-image ghcr.io/YOUR_USER/talos-nftables:v0.1.0

docker load -i _out/installer/installer-amd64.tar
docker tag ghcr.io/siderolabs/installer-base:v1.13.3 \
  ghcr.io/YOUR_USER/talos-installer:v1.13.3-nft0.1.0
docker push ghcr.io/YOUR_USER/talos-installer:v1.13.3-nft0.1.0
```

Talos imager writes the custom archive with the `installer-base` image tag; retag the **just-loaded** image before pushing it. Do not push to the `siderolabs` namespace. An ARM64 version was built and loaded in the lab; the AMD64 installer recipe has not yet been run on a Talos VM.

For a new installation, set `machine.install.image` in the machine config to your custom installer before applying it. For an existing node, use `talosctl upgrade --image ghcr.io/YOUR_USER/talos-installer:v1.13.3-nft0.1.0` with your normal Talos upgrade procedure. Include any other system extensions already used by that node when building the installer; the new image defines the complete extension set.

## 3. Supply rules

Append [the example ExtensionServiceConfig](../examples/extension-service-config.yaml) as a separate YAML document in the machine config. Set `name: nft-rules`, keep the mount path `/etc/nft-rules/rules.nft`, and edit the nft `content` as required. The extension service will wait until this document exists.

The rules may be changed through machine config without another installer build. Upgrading the loader or its `nft` binary requires a new extension image and a Talos upgrade.

## 4. Include it in the first boot image when needed

If filtering is needed before installation, build an ISO containing the extension too. An ISO without the extension leaves the node unprotected until installation and reboot.

```bash
mkdir -p _out/iso
docker run --rm \
  -v "$PWD/_out/iso:/out" \
  ghcr.io/siderolabs/imager:v1.13.3 iso \
  --arch amd64 \
  --image-cache ghcr.io/siderolabs/installer-base:v1.13.3 \
  --system-extension-image ghcr.io/YOUR_USER/talos-nftables:v0.1.0
```

The lab assembled and booted the ARM64 equivalent. To activate the service in maintenance mode, a suitable machine configuration containing the `ExtensionServiceConfig` must also be available; the service deliberately waits for it.
