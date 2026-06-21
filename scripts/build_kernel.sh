#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

show_target_banner "Building Linux Kernel"

KERNEL_DIR="../kernel/oneplus/sdm845/linux-sdm845"

cd $KERNEL_DIR
print_info "Restoring base postmarketOS kernel config..."
cp ../config-postmarketos-qcom-sdm845.aarch64 .config

# THE 8:41 AM IST (MAY 22nd) GOLDEN CONFIG + TOUCHSCREEN FIX
print_info "Generating debug configuration fragment..."
cat << EOF > debug.config
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_RAM=y
CONFIG_EFI=y
CONFIG_EFI_ZBOOT=y
CONFIG_CMDLINE="${KERNEL_CMDLINE}"
CONFIG_CMDLINE_EXTEND=y
# CRITICAL DISPLAY FIXES
CONFIG_REGULATOR_QCOM_REFGEN=y
CONFIG_REGULATOR_QCOM_LABIBB=y
# TOUCHSCREEN BUILT-IN (RMI4)
CONFIG_INPUT_RMI4=y
CONFIG_RMI4_I2C=y
CONFIG_RMI4_F03=y
CONFIG_RMI4_F03_SERIO=y
CONFIG_RMI4_2D_SENSOR=y
CONFIG_RMI4_F11=y
CONFIG_RMI4_F12=y
CONFIG_RMI4_F30=y
CONFIG_RMI4_F3A=y
CONFIG_RMI4_F54=y
CONFIG_RMI4_F55=y
# OFFLINE CHARGING (PMI8998 & BQ27441)
CONFIG_BATTERY_BQ27XXX=y
CONFIG_BATTERY_BQ27XXX_I2C=y
CONFIG_CHARGER_QCOM_SMB2=y
CONFIG_QCOM_SPMI_RRADC=y
# DISABLE TUX LOGO
CONFIG_LOGO=n
# CONFIG_LOGO_LINUX_CLUT224 is not set
EOF

print_info "Merging kernel configurations..."
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- scripts/kconfig/merge_config.sh -m .config debug.config
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make olddefconfig

print_info "Compiling Linux kernel sources, DTBs, and EFI stub..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image Image.gz dtbs vmlinuz.efi

print_success "Kernel and Device Tree Blobs compiled successfully!"

