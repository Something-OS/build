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
# Parse KERNEL_DEFCONFIG (can be space-separated config files/fragments)
read -r -a CONFIG_FILES <<< "$KERNEL_DEFCONFIG"

# Restore base configuration from the first config file
BASE_CONFIG="${CONFIG_FILES[0]}"
print_info "Restoring base kernel config from $BASE_CONFIG..."
if [[ "$BASE_CONFIG" = /* ]]; then
    cp "$BASE_CONFIG" .config
else
    cp "$PROJECT_ROOT/$BASE_CONFIG" .config
fi

# Generate base debug configuration fragment
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

# Append any additional config fragments specified in KERNEL_DEFCONFIG
for ((i=1; i<${#CONFIG_FILES[@]}; i++)); do
    EXTRA_CONFIG="${CONFIG_FILES[i]}"
    print_info "Appending config fragment: $EXTRA_CONFIG..."
    if [[ "$EXTRA_CONFIG" = /* ]]; then
        cat "$EXTRA_CONFIG" >> debug.config
    else
        cat "$PROJECT_ROOT/$EXTRA_CONFIG" >> debug.config
    fi
done

print_info "Merging kernel configurations..."
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- scripts/kconfig/merge_config.sh -m .config debug.config
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make olddefconfig

print_info "Compiling Linux kernel sources, DTBs, and EFI stub..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image Image.gz dtbs vmlinuz.efi

print_success "Kernel and Device Tree Blobs compiled successfully!"

