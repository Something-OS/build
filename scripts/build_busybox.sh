#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

cd "$WORKSPACE/tools"

BUSYBOX_VER="1.36.1"

if [ ! -d "busybox-${BUSYBOX_VER}" ]; then
    print_info "Downloading BusyBox..."
    wget -q https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2
    tar -xf busybox-${BUSYBOX_VER}.tar.bz2
fi

cd busybox-${BUSYBOX_VER}

print_info "Configuring BusyBox..."
# Run defconfig to get a base configuration
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig

# We need a static binary because we won't have shared libraries in our initramfs
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Disable the 'tc' applet — it uses CBQ traffic control structs (TCA_CBQ_*,
# tc_cbq_wrropt, etc.) that were removed from modern Linux kernel headers (6.x).
# We don't need traffic control shaping on our simple OS anyway.
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config

# Use yes "" | make oldconfig to non-interactively confirm defaults for new options
yes "" | make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- oldconfig

print_info "Compiling BusyBox..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

print_info "Installing BusyBox to _install..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- install

print_success "BusyBox built successfully! The rootfs skeleton is in tools/busybox-${BUSYBOX_VER}/_install"

