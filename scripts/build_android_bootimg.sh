#!/bin/bash
set -e

# Run from build directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

OUT_DIR="$(mkdir -p ../out/target/product/${DEVICE} && cd ../out/target/product/${DEVICE} && pwd)"
BUSYBOX_VER="1.36.1"
KERNEL_DIR="../../android_kernel_oneplus_sdm845/out"

if [ ! -d "tools/aosp-mkbootimg" ]; then
    print_info "Cloning AOSP mkbootimg tool..."
    mkdir -p tools
    git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg tools/aosp-mkbootimg
fi
MKBOOTIMG="python3 tools/aosp-mkbootimg/mkbootimg.py"

KERNEL_WITH_DTB="${KERNEL_DIR}/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "${KERNEL_WITH_DTB}" ]; then
    print_warn "Android Kernel not found at ${KERNEL_WITH_DTB}. This script may be legacy."
fi

print_info "Packing initramfs..."
# Assuming initramfs is in boot/initramfs
if [ -d "boot/initramfs" ]; then
    cd boot/initramfs
    find . | cpio -ov -H newc > "${OUT_DIR}/initramfs_android.cpio"
    cd ../..
    gzip -9 -f "${OUT_DIR}/initramfs_android.cpio"
else
    print_error "boot/initramfs not found"
    exit 1
fi

print_info "Creating boot_android.img (Header V0 + Image.gz-dtb + pmaports offsets)..."

if [ -f "${KERNEL_WITH_DTB}" ]; then
    $MKBOOTIMG \
      --kernel ${KERNEL_WITH_DTB} \
      --ramdisk "${OUT_DIR}/initramfs_android.cpio.gz" \
      --cmdline "${KERNEL_CMDLINE}" \
      --base ${BOOTIMG_BASE} \
      --kernel_offset ${BOOTIMG_KERNEL_OFFSET} \
      --ramdisk_offset ${BOOTIMG_RAMDISK_OFFSET} \
      --second_offset ${BOOTIMG_SECOND_OFFSET} \
      --tags_offset ${BOOTIMG_TAGS_OFFSET} \
      --pagesize ${BOOTIMG_PAGESIZE} \
      --header_version ${BOOTIMG_HEADER_VERSION} \
      -o "${OUT_DIR}/boot_android.img"

    print_success "Created ${OUT_DIR}/boot_android.img!"
fi

