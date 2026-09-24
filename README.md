# cuos-gpu-os

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

Boot-tested on the real GEX44. `nvidia-smi` and `nvidia`/`nvidia-drm`/
`nvidia-modeset` all come up fine on their own, but two things needed an
explicit fixup — both handled by [`gpu-setup.sh`](system/gpu-setup.sh), run by
`gpu-setup.service` between `cuos-init.service` and `docker.service`:

- **`nvidia-uvm` doesn't load under its expected name.** `nvidia-kernel-dkms`
  (which sets up the `nvidia-uvm` → real-module modprobe alias) only exists in
  the builder stage; the final image only has the `.ko` files, under their
  Debian-alternatives name (`nvidia-current-uvm`). Without it loaded, CUDA
  fails with `ggml_cuda_init: failed to initialize CUDA: unknown error` even
  though `nvidia-smi` works fine (it doesn't need uvm).
- **`/dev/nvidia-uvm[-tools]` don't get created.** This image ships no
  `nvidia-modprobe` helper, so nothing creates them after the module loads;
  `gpu-setup.sh` does it from `/proc/devices` (the major number is assigned
  dynamically per boot, not fixed).
- **`/etc/docker/daemon.json`'s `nvidia` runtime doesn't survive a boot.**
  `cuos-init`'s `configure_docker()` (in cuos-dev/cuos's `init.sh`)
  regenerates that file from scratch on every boot, wiping whatever
  `nvidia-ctk runtime configure` wrote into the image at build time.
  `gpu-setup.sh` reapplies it at boot, after cuos-init and before dockerd
  starts.

Verify on a fresh boot:

- `nvidia-smi` shows the GPU
- `systemctl status gpu-setup.service` succeeded
- `ls /dev/nvidia-uvm*` shows both device nodes
- `docker info | grep -i runtime` lists `nvidia` as the default
- a test container actually gets the GPU: `docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi`

If the dkms build fails during `docker build` (kernel headers/driver series
mismatch), check the current `nvidia-driver` version for Debian trixie at
<https://packages.debian.org/trixie/nvidia-driver> — driver series move on.

## Building and publishing

Pushing a tag matching `v*` (or running the *Build and publish image* workflow
manually) builds `system/Dockerfile` and publishes it to
`ghcr.io/kbe-solvis/cuos-gpu-os` — see
[`.github/workflows/build.yml`](.github/workflows/build.yml). The resulting
digest is printed in the workflow run's summary.

To build and publish locally instead:

```sh
docker build -t ghcr.io/kbe-solvis/cuos-gpu-os:v0.6.1-gpu1 -f system/Dockerfile system/
docker push ghcr.io/kbe-solvis/cuos-gpu-os:v0.6.1-gpu1
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/kbe-solvis/cuos-gpu-os:v0.6.1-gpu1
```

Then in `solvis-llm-system/system.json`, point at what you published:

```json
{
  "os_image": "ghcr.io/kbe-solvis/cuos-gpu-os",
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
