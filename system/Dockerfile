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
# Verified on the real GEX44: nvidia-smi and the docker runtime registration
# both need help surviving a real boot that cuos-init's configure_docker()
# controls -- see gpu-setup.sh/.service below for why and what they patch up.

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
# a container can be given GPU access. This registration only affects the
# daemon.json baked into *this image layer* -- cuos-init overwrites the real
# /etc/docker/daemon.json from scratch on every boot (configure_docker() in
# cuos-dev/cuos's system/cuos/init.sh), so it doesn't survive a real boot on
# its own. gpu-setup.service (below) redoes it after cuos-init and before
# dockerd starts, which is what actually matters at runtime; this build-time
# run just keeps the image usable standalone (e.g. `docker run` outside CuOS).
RUN curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list \
  && apt-get update && apt-get install --no-install-recommends -y \
      nvidia-container-toolkit \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && nvidia-ctk runtime configure --runtime=docker --config=/etc/docker/daemon.json

# Boot-time fixups cuos-init and the driver/toolkit packages don't cover on
# their own -- see gpu-setup.sh for the two reasons why. Installed the same
# way cuos-dev/cuos's own install.sh wires up cuos-init.service: symlink into
# /etc/systemd/system, then enable.
COPY gpu-setup.sh gpu-setup.service /usr/local/cuos/
RUN chmod +x /usr/local/cuos/gpu-setup.sh \
  && ln -sf /usr/local/cuos/gpu-setup.service /etc/systemd/system/gpu-setup.service \
  && systemctl enable gpu-setup.service
