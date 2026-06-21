#!/bin/bash

# Configuration loader for Something OS build scripts.
# Sourced by other build scripts.

if [ -z "$DEVICE" ]; then
    if [ -n "$1" ]; then
        DEVICE="$1"
    else
        DEVICE="fajita"
    fi
fi

# Find the device BoardConfig.mk, looking at relative locations
CONFIG_FILE=""
if [ -f "device/oneplus/${DEVICE}/BoardConfig.mk" ]; then
    CONFIG_FILE="device/oneplus/${DEVICE}/BoardConfig.mk"
elif [ -f "../device/oneplus/${DEVICE}/BoardConfig.mk" ]; then
    CONFIG_FILE="../device/oneplus/${DEVICE}/BoardConfig.mk"
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: BoardConfig.mk for device '$DEVICE' not found!" >&2
    exit 1
fi

get_config() {
    local key="$1"
    local val=$(grep -E "^${key}[[:space:]]*:?=" "$CONFIG_FILE" | head -n1 | sed -E "s/^${key}[[:space:]]*:?=[[:space:]]*//")
    echo "$val" | sed -e 's/^"//' -e 's/"$//'
}

# Export all variables needed by the build scripts
export DEVICE_NAME=$(get_config "BOARD_DEVICE_NAME")
export KERNEL_DTB=$(get_config "BOARD_KERNEL_DTB")
export KERNEL_CMDLINE=$(get_config "BOARD_KERNEL_CMDLINE")
export BOOTIMG_BASE=$(get_config "BOARD_BOOTIMG_BASE")
export BOOTIMG_KERNEL_OFFSET=$(get_config "BOARD_BOOTIMG_KERNEL_OFFSET")
export BOOTIMG_RAMDISK_OFFSET=$(get_config "BOARD_BOOTIMG_RAMDISK_OFFSET")
export BOOTIMG_SECOND_OFFSET=$(get_config "BOARD_BOOTIMG_SECOND_OFFSET")
export BOOTIMG_TAGS_OFFSET=$(get_config "BOARD_BOOTIMG_TAGS_OFFSET")
export BOOTIMG_PAGESIZE=$(get_config "BOARD_BOOTIMG_PAGESIZE")
export BOOTIMG_HEADER_VERSION=$(get_config "BOARD_BOOTIMG_HEADER_VERSION")
export UFS_PARTITION=$(get_config "BOARD_UFS_PARTITION")
export LOOP_OFFSET=$(get_config "BOARD_LOOP_OFFSET")
export ROOTFS_LABEL=$(get_config "BOARD_ROOTFS_LABEL")
export DEVICE_DIR="$(dirname "$CONFIG_FILE")"

# ANSI color codes for Android ROM-style logging
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m'

print_info() {
    echo -e "${BLUE}[Something OS]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[Something OS]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[Something OS]${NC} $1"
}

print_error() {
    echo -e "${RED}[Something OS]${NC} $1"
}

show_target_banner() {
    local action="$1"
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}  Something OS Build System - ${action}${NC}"
    echo -e "  Target Device      : ${GREEN}${DEVICE}${NC}"
    echo -e "  Target Product     : ${GREEN}${DEVICE_NAME}${NC}"
    echo -e "  Kernel DTB Target  : ${YELLOW}${KERNEL_DTB}${NC}"
    echo -e "  Base Partition     : ${YELLOW}${UFS_PARTITION}${NC}"
    echo -e "  Output Location    : ${PURPLE}${OUT_DIR:-out/target/product/${DEVICE}}${NC}"
    echo -e "${CYAN}===========================================${NC}"
}


