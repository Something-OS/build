#!/bin/bash
set -e
# Run from build directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

BOARD_UFS_PARTITION="${BOARD_UFS_PARTITION:-$UFS_PARTITION}"
BOARD_LOOP_OFFSET="${BOARD_LOOP_OFFSET:-$LOOP_OFFSET}"

show_target_banner "Building Boot Image"


BUSYBOX_DIR="tools/busybox-1.36.1"
KERNEL_DIR="../kernel/oneplus/sdm845/linux-sdm845"
ROOTFS_DIR="../rootfs"
BOOT_DIR="boot"
OUT_DIR="$(mkdir -p ../out/target/product/${DEVICE} && cd ../out/target/product/${DEVICE} && pwd)"
IMAGES_DIR="$OUT_DIR"
TOOLS_DIR="tools"
SRC_DIR="src/something_charger"
REC_SRC_DIR="src/something_recovery"

mkdir -p ${BOOT_DIR}
print_info "Compiling early charger binary..."
aarch64-linux-gnu-gcc -static -O3 ${SRC_DIR}/something_charger.c -o ${BOOT_DIR}/something_charger -lm
print_info "Compiling boot animation binary..."
aarch64-linux-gnu-gcc -static -O3 ${SRC_DIR}/something_bootanim.c -o ${BOOT_DIR}/something_bootanim -lm
print_info "Compiling custom recovery binary..."
aarch64-linux-gnu-gcc -static -O3 -DBOARD_UFS_PARTITION="\"${BOARD_UFS_PARTITION}\"" -DBOARD_LOOP_OFFSET="\"${BOARD_LOOP_OFFSET}\"" ${REC_SRC_DIR}/something_recovery.c -o ${BOOT_DIR}/something_recovery -lm

print_info "Creating initramfs directory layout..."
rm -rf ${BOOT_DIR}/initramfs
mkdir -p ${BOOT_DIR}/initramfs/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,sysroot,lib/aarch64-linux-gnu,tmp}
cp -a ${BUSYBOX_DIR}/_install/* ${BOOT_DIR}/initramfs/

# Bundle repair tools
print_info "Importing recovery tools and system libraries from base rootfs..."
cp -L ${ROOTFS_DIR}/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 ${BOOT_DIR}/initramfs/lib/
for lib in libext2fs.so.2 libcom_err.so.2 libblkid.so.1 libuuid.so.1 libe2p.so.2 libc.so.6; do
    cp -L ${ROOTFS_DIR}/lib/aarch64-linux-gnu/${lib} ${BOOT_DIR}/initramfs/lib/aarch64-linux-gnu/
    cp -L ${ROOTFS_DIR}/lib/aarch64-linux-gnu/${lib} ${BOOT_DIR}/initramfs/lib/
done
cp -L ${ROOTFS_DIR}/sbin/e2fsck ${BOOT_DIR}/initramfs/sbin/e2fsck
# NOTE: Do NOT copy rootfs mke2fs — BusyBox installs sbin/mke2fs as a symlink
# to ../bin/busybox. Copying over it would overwrite the static BusyBox binary.

print_info "Importing GPU firmware..."
mkdir -p ${BOOT_DIR}/initramfs/lib/firmware/qcom/sdm845/OnePlus/enchilada
mkdir -p ${BOOT_DIR}/initramfs/lib/firmware/qcom/sdm845/oneplus6
cp -L ${ROOTFS_DIR}/lib/firmware/qcom/a630_gmu.bin ${BOOT_DIR}/initramfs/lib/firmware/qcom/
cp -L ${ROOTFS_DIR}/lib/firmware/qcom/a630_sqe.fw ${BOOT_DIR}/initramfs/lib/firmware/qcom/
cp -L ${ROOTFS_DIR}/lib/firmware/qcom/sdm845/OnePlus/enchilada/a630_zap.mbn ${BOOT_DIR}/initramfs/lib/firmware/qcom/sdm845/OnePlus/enchilada/
cp -L ${ROOTFS_DIR}/lib/firmware/qcom/sdm845/oneplus6/a630_zap.mbn ${BOOT_DIR}/initramfs/lib/firmware/qcom/sdm845/oneplus6/

cp ${BOOT_DIR}/something_charger ${BOOT_DIR}/initramfs/bin/something_charger
cp ${BOOT_DIR}/something_bootanim ${BOOT_DIR}/initramfs/bin/something_bootanim
cp ${BOOT_DIR}/something_recovery ${BOOT_DIR}/initramfs/bin/something_recovery

# CRITICAL: Re-enforce the static BusyBox binary last, in case any earlier cp
# followed a symlink and clobbered it (e.g. mke2fs -> ../bin/busybox).
cp ${BUSYBOX_DIR}/_install/bin/busybox ${BOOT_DIR}/initramfs/bin/busybox
ln -sf /init ${BOOT_DIR}/initramfs/bin/init

print_info "Generating custom early-init boot script..."
cat << INIT_EOF > ${BOOT_DIR}/initramfs/init
#!/bin/sh
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sys /sys
/bin/busybox mount -t devtmpfs dev /dev
/bin/busybox mkdir -p /dev/pts
/bin/busybox mount -t devpts devpts /dev/pts

# --- SOMETHING OS RENDERER (C) ---
if grep -qE "androidboot.mode=charger|androidboot.mode=offmode_charging|androidboot.startupmode=charger|androidboot.charger=1" /proc/cmdline; then
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
    echo 255 > /sys/class/backlight/backlight/brightness 2>/dev/null
    /bin/something_charger
    /bin/busybox reboot
fi

# Boot Animation
echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
echo 255 > /sys/class/backlight/backlight/brightness 2>/dev/null
/bin/something_bootanim &
ANIM_PID=\$!

echo "=================================================="
echo "  OnePlus 6T NUCLEAR RESET BOOT                   "
echo "=================================================="

# 1. Wait for UFS
for i in \$(seq 1 10); do [ -b ${BOARD_UFS_PARTITION} ] && break; sleep 1; done

# 2. Manual GPT Offset Mount
echo "[*] Mapping partition..."
/bin/busybox losetup -o ${BOARD_LOOP_OFFSET} /dev/loop2 ${BOARD_UFS_PARTITION}
/bin/busybox sleep 1

# 3. FORCED REPAIR
echo "[*] Running Forced FS Repair..."
LD_LIBRARY_PATH=/lib/aarch64-linux-gnu /sbin/e2fsck -y /dev/loop2

# 4. MOUNT AND START
/bin/busybox mkdir -p /sysroot
echo "[*] Mounting Ubuntu..."
if /bin/busybox mount -t ext4 -o rw,noatime /dev/loop2 /sysroot; then
    echo "[✓] MOUNT SUCCESSFUL."

    # Ensure critical permissions
    /bin/busybox chmod 4755 /sysroot/usr/bin/sudo 2>/dev/null || true

    echo "[INFO] Terminating boot animation..."
    if [ -n "\$ANIM_PID" ]; then
        /bin/busybox kill -9 \$ANIM_PID 2>/dev/null || true
    fi

    echo "[✓] STARTING SYSTEMD..."
    /bin/busybox umount /dev/pts 2>/dev/null || true
    /bin/busybox umount /sys 2>/dev/null || true
    /bin/busybox umount /proc 2>/dev/null || true

    exec /bin/busybox switch_root /sysroot /sbin/init
else
    echo "ERROR: Mount failed."
    /bin/busybox sh
fi
INIT_EOF
chmod +x ${BOOT_DIR}/initramfs/init

print_info "Compressing initramfs ramdisk image..."
(cd ${BOOT_DIR}/initramfs && find . | cpio -ov -H newc > ${IMAGES_DIR}/initramfs.cpio 2>/dev/null)
gzip -9 -f ${IMAGES_DIR}/initramfs.cpio

if [ -f "../device/oneplus/${DEVICE}/Image.gz-dtb" ]; then
    print_info "Using prebuilt kernel Image.gz-dtb..."
    cp "../device/oneplus/${DEVICE}/Image.gz-dtb" ${IMAGES_DIR}/Image.gz-dtb
else
    print_info "Concatenating kernel Image.gz with Device Tree Blobs..."
    DTB="${KERNEL_DIR}/arch/arm64/boot/dts/${KERNEL_DTB}"
    KERNEL="${KERNEL_DIR}/arch/arm64/boot/Image.gz"
    cat ${KERNEL} ${DTB} > ${IMAGES_DIR}/Image.gz-dtb
fi

print_info "Running mkbootimg to package target boot.img..."
python3 ${TOOLS_DIR}/aosp-mkbootimg/mkbootimg.py \
    --kernel ${IMAGES_DIR}/Image.gz-dtb \
    --ramdisk ${IMAGES_DIR}/initramfs.cpio.gz \
    --cmdline "${KERNEL_CMDLINE}" \
    --base ${BOOTIMG_BASE} \
    --kernel_offset ${BOOTIMG_KERNEL_OFFSET} \
    --ramdisk_offset ${BOOTIMG_RAMDISK_OFFSET} \
    --second_offset ${BOOTIMG_SECOND_OFFSET} \
    --tags_offset ${BOOTIMG_TAGS_OFFSET} \
    --pagesize ${BOOTIMG_PAGESIZE} \
    --header_version ${BOOTIMG_HEADER_VERSION} \
    -o ${IMAGES_DIR}/boot.img

print_success "Boot image successfully created: out/target/product/${DEVICE}/boot.img"

