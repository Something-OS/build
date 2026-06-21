#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

show_target_banner "Building Linux Kernel"

PROJECT_ROOT="$(cd "${WORKSPACE}/.." && pwd)"
KERNEL_DIR_PATH="$PROJECT_ROOT/$KERNEL_DIR"

cd "$KERNEL_DIR_PATH"
print_info "Restoring base kernel config from $KERNEL_DEFCONFIG..."
cp "$PROJECT_ROOT/$KERNEL_DEFCONFIG" .config

# Generate debug configuration fragment with general requirements
print_info "Generating base debug configuration fragment..."
cat << EOF > debug.config
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_RAM=y
CONFIG_EFI=y
CONFIG_EFI_ZBOOT=y
CONFIG_CMDLINE="${KERNEL_CMDLINE}"
CONFIG_CMDLINE_EXTEND=y
# DISABLE TUX LOGO
CONFIG_LOGO=n
# CONFIG_LOGO_LINUX_CLUT224 is not set
EOF

# Append device-specific configs if present
if [ -f "$DEVICE_DIR/kernel.config" ]; then
    print_info "Appending device-specific kernel configurations from $DEVICE_DIR/kernel.config..."
    cat "$DEVICE_DIR/kernel.config" >> debug.config
fi

print_info "Merging kernel configurations..."
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- scripts/kconfig/merge_config.sh -m .config debug.config
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make olddefconfig

print_info "Compiling Linux kernel sources, DTBs, and EFI stub..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image Image.gz dtbs vmlinuz.efi

print_success "Kernel and Device Tree Blobs compiled successfully!"

