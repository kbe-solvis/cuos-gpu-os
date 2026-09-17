# SPDX-License-Identifier: MIT-0
#
# CuOS system image + NVIDIA GPU support, for a Hetzner GEX44 (RTX 4000 SFF
# Ada). Built FROM the published cuos-system image -- bootloader, init and the
# updater hooks all stay as CuOS ships them; this only adds what the GPU needs
# on top.
#
# Two stages: the kernel module has to be compiled with dkms against this
# image's exact kernel headers (not the build host's running kernel -- that's
# the normal way to bake a kernel module into a container image), but nothing
# in the compiler toolchain (gcc, binutils, linux-headers, dkms itself) is
# needed once the .ko files exist. The final stage installs only the runtime
# pieces and copies the already-built modules over.
#
# UNVERIFIED: this has not been build- or boot-tested on real GEX44 hardware.
# After the first boot, check `nvidia-smi` and `dmesg | grep -i nvidia`.

FROM ghcr.io/cuos-dev/cuos-system:v0.6.1 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# cuos-system symlinks /var/log (and other state dirs) to /data/*, which is
# only populated at runtime by the @data subvolume. At build time those
# targets don't exist, so anything writing through the symlink (dpkg,
# update-alternatives) fails. Create the real targets first; the @data
# subvolume mount hides them again at runtime, same as on a stock image.
RUN mkdir -p /data/log/apt /data/dhcp /data/docker /data/containerd /data/root

# nvidia-kernel-dkms lives in "non-free"; "non-free-firmware" is already
# enabled by the base image (for the CPU microcode packages).
RUN sed -i 's/^Components: main non-free-firmware$/Components: main contrib non-free non-free-firmware/' \
      /etc/apt/sources.list.d/debian.sources

# Only what's needed to compile the module -- not the nvidia-driver
# metapackage, which also pulls Xorg/GLX/VDPAU packages this headless box has
# no use for.
RUN apt-get update && apt-get install --no-install-recommends -y \
      linux-headers-amd64 \
      build-essential \
      dkms \
      nvidia-kernel-dkms \
  && apt-get clean && rm -rf /var/lib/apt/lists/*


FROM ghcr.io/cuos-dev/cuos-system:v0.6.1
ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir -p /data/log/apt /data/dhcp /data/docker /data/containerd /data/root

RUN sed -i 's/^Components: main non-free-firmware$/Components: main contrib non-free non-free-firmware/' \
      /etc/apt/sources.list.d/debian.sources

# Runtime-only packages: the userspace driver bits nvidia-smi needs
# (nvidia-alternative, libnvidia-ml1), the GSP firmware blob Ada Lovelace
# cards (RTX 4000 SFF Ada) need to initialise, and nvidia-support for the
# nouveau blacklist -- without it the in-kernel open-source driver can grab
# the card before the proprietary one does. No gcc/dkms/headers here.
RUN apt-get update && apt-get install --no-install-recommends -y \
      gnupg \
      nvidia-alternative \
      libnvidia-ml1 \
      nvidia-smi \
      nvidia-support \
      firmware-nvidia-gsp \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# nvidia-support does NOT ship this (checked -- it only has a mismatch-report
# script and docs) even though the kernel does carry nouveau.ko. Without a
# blacklist, nouveau can bind the card first and keep the proprietary driver
# from loading at all -- the standard NVIDIA-installer fix.
RUN printf 'blacklist nouveau\noptions nouveau modeset=0\n' \
      > /etc/modprobe.d/nvidia-blacklist-nouveau.conf

# The dkms-built kernel modules, without dkms or the compiler that built them.
COPY --from=builder /lib/modules/ /tmp/builder-modules/
RUN KVER="$(ls /lib/modules)" \
  && cp -a "/tmp/builder-modules/${KVER}/updates" "/lib/modules/${KVER}/updates" \
  && rm -rf /tmp/builder-modules \
  && depmod "${KVER}" \
  && update-initramfs -u -k "${KVER}"

# NVIDIA Container Toolkit: registers the "nvidia" OCI runtime with dockerd so
# a container can be given GPU access.
RUN curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list \
  && apt-get update && apt-get install --no-install-recommends -y \
      nvidia-container-toolkit \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && nvidia-ctk runtime configure --runtime=docker --config=/etc/docker/daemon.json
