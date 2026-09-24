#!/bin/sh
# SPDX-License-Identifier: MIT-0
#
# Runs once per boot, between cuos-init.service and docker.service (see
# gpu-setup.service). Two things the shipped driver/toolkit packages don't
# handle on their own in this image:
#
# 1. nvidia-kernel-dkms (which normally sets up the "nvidia-uvm" modprobe
#    alias) only exists in the Dockerfile's builder stage, not the final one,
#    so the uvm module has to be loaded by its real, alternatives-renamed
#    name -- "modprobe nvidia_uvm"/"nvidia-uvm" doesn't resolve here.
# 2. This image ships no nvidia-modprobe helper, so nothing else creates
#    /dev/nvidia-uvm[-tools]; CUDA needs them to initialise even though
#    nvidia-smi works fine without them. Create them from /proc/devices
#    (major number is assigned dynamically at module load, not fixed).
#
# Also: cuos-init's configure_docker() (system/cuos/init.sh in the cuos-dev/
# cuos repo) regenerates /etc/docker/daemon.json from scratch on every boot,
# which wipes the "nvidia" runtime this image's Dockerfile registers at
# *build* time via `nvidia-ctk runtime configure`. Re-apply it here, after
# cuos-init has written the file and before dockerd reads it.
set -e

UVM_MODULE="nvidia-current-uvm"
modprobe "${UVM_MODULE}"

UVM_MAJOR="$(awk '$2 == "nvidia-uvm" { print $1 }' /proc/devices)"
if [ -n "${UVM_MAJOR}" ]; then
  [ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "${UVM_MAJOR}" 0
  [ -e /dev/nvidia-uvm-tools ] || mknod -m 666 /dev/nvidia-uvm-tools c "${UVM_MAJOR}" 1
fi

nvidia-ctk runtime configure --runtime=docker --config=/etc/docker/daemon.json --set-as-default
