# solvis-llm-os

A CuOS system image with NVIDIA GPU support baked in, for the Hetzner GEX44
(RTX 4000 SFF Ada) that [`solvis-llm-system`](../solvis-llm-system) runs on.

This is the ["Own OS based on the CuOS system"](https://github.com/cuos-dev/cuos/blob/HEAD/docs/development-guide.md#own-os-based-on-the-cuos-system)
level: everything CuOS itself needs (bootloader, init, the updater's kernel
hooks) stays exactly as published — this repo only adds the NVIDIA driver and
the NVIDIA Container Toolkit on top, in [`system/Dockerfile`](system/Dockerfile).

No custom updater image is needed: the kernel and boot chain are untouched
(still the stock `linux-image-amd64` GRUB chain), so the stock
`ghcr.io/cuos-dev/cuos-updater` from `cuos-release`'s `release.json` is used
as-is.

## Status

Two-stage build: `builder` compiles the driver via dkms (needs
`linux-headers-amd64`, `build-essential`, `dkms`); the final stage installs
only the runtime packages (`nvidia-alternative`, `libnvidia-ml1`, `nvidia-smi`,
`nvidia-support`, `firmware-nvidia-gsp`) and copies the already-built `.ko`
files over — no compiler, dkms or headers in the shipped image. 731 MB base →
1.14 GB (a single-stage build with the full `nvidia-driver` metapackage,
including Xorg/GLX/VDPAU this headless box doesn't need, came to 1.83 GB).

Checked in this build environment (no GPU here, so this is as far as it goes):

- `nvidia` runtime registered in `/etc/docker/daemon.json`
- driver packages configure cleanly, dkms builds and signs all five kernel
  modules (`nvidia`, `nvidia-drm`, `nvidia-modeset`, `nvidia-uvm`,
  `nvidia-peermem`) for `6.12.107+deb13-amd64`, and they survive the copy into
  the final stage
- `nvidia-smi`'s shared library dependencies all resolve (`ldd`)
- **`nvidia-support` does not blacklist `nouveau`** despite the kernel
  shipping `nouveau.ko` — without a blacklist it can bind the card first and
  keep the proprietary driver from loading at all. Added explicitly
  (`/etc/modprobe.d/nvidia-blacklist-nouveau.conf`, baked into the initrd).

What's still unverified: whether the module actually loads against the real
RTX 4000 SFF Ada and whether a container gets the GPU through the toolkit end
to end. Check on first boot:

- `nvidia-smi` shows the GPU
- `dmesg | grep -i nvidia` has no module load errors
- `docker info | grep -i runtime` lists `nvidia`
- a test container actually gets the GPU: `docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi`

If the dkms build fails during `docker build` (kernel headers/driver series
mismatch), check the current `nvidia-driver` version for Debian trixie at
<https://packages.debian.org/trixie/nvidia-driver> — driver series move on.

## Building and publishing

```sh
docker build -t ghcr.io/<you>/solvis-llm-os:v0.6.1-gpu1 -f system/Dockerfile system/
docker push ghcr.io/<you>/solvis-llm-os:v0.6.1-gpu1
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/<you>/solvis-llm-os:v0.6.1-gpu1
```

Then in `solvis-llm-system/system.json`, point at what you published:

```json
{
  "os_image": "ghcr.io/<you>/solvis-llm-os",
  "os_image_version": "v0.6.1-gpu1",
  "os_image_digest": "sha256:..."
}
```

The digest is what makes the build reproducible — a mismatch is fatal rather
than silently accepted, so update all three together whenever you rebuild.

## Bumping the CuOS base version

`FROM ghcr.io/cuos-dev/cuos-system:v0.6.1` is pinned to the version currently
in `cuos-release/release.json`. When that moves, bump the tag here too and
rebuild — otherwise the OS falls behind while the rest of the system (updater,
IaC) tracks the new release.
