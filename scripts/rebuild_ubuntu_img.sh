#!/bin/bash
set -e
# Run from build directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

show_target_banner "Building System Rootfs Image"


ROOTFS="../rootfs"
OUT_DIR="$(mkdir -p ../out/target/product/${DEVICE} && cd ../out/target/product/${DEVICE} && pwd)"
IMAGE="${OUT_DIR}/ubuntu.img"
SPARSE_IMAGE="${OUT_DIR}/ubuntu_sparse.img"

# 1. Clean
print_info "Cleaning apt cache in rootfs..."
sudo rm -rf ${ROOTFS}/var/cache/apt/archives/*.deb
rm -f "$IMAGE" "$SPARSE_IMAGE"

# 2. Apply overlay (tracked config files on top of the base rootfs)
# We support common overlays and device-specific overrides
COMMON_OVERLAY="rootfs-overlay/common"
DEVICE_OVERLAY="${DEVICE_DIR}/rootfs-overlay"

if [ -d "$COMMON_OVERLAY" ]; then
    print_info "Applying common rootfs overlay from ${COMMON_OVERLAY}..."
    sudo cp -av --no-preserve=timestamps "$COMMON_OVERLAY"/. "$ROOTFS"/
fi

if [ -d "$DEVICE_OVERLAY" ]; then
    print_info "Applying device-specific rootfs overlay for ${DEVICE} from ${DEVICE_OVERLAY}..."
    sudo cp -av --no-preserve=timestamps "$DEVICE_OVERLAY"/. "$ROOTFS"/
else
    print_warn "No device-specific overlay directory found for ${DEVICE} at ${DEVICE_OVERLAY}."
fi

# 2b. Copy system.prop to rootfs
if [ -f "${DEVICE_DIR}/system.prop" ]; then
    print_info "Copying device system properties to rootfs..."
    sudo cp "${DEVICE_DIR}/system.prop" "${ROOTFS}/etc/system.prop"
fi

# 2c. Configure default UI session
TARGET_SESSION="${DEFAULT_UI:-androidshell}"
print_info "Configuring default UI session to: ${TARGET_SESSION}..."

if [ -f "${ROOTFS}/var/lib/AccountsService/users/ubuntu" ]; then
    sudo sed -i "s/^Session=.*/Session=${TARGET_SESSION}/" "${ROOTFS}/var/lib/AccountsService/users/ubuntu"
else
    sudo mkdir -p "${ROOTFS}/var/lib/AccountsService/users"
    sudo tee "${ROOTFS}/var/lib/AccountsService/users/ubuntu" > /dev/null << SESSIONEOF
[User]
Session=${TARGET_SESSION}
SystemAccount=false
SESSIONEOF
fi

if [ -f "${ROOTFS}/etc/gdm3/custom.conf" ]; then
    if sudo grep -q "^AutomaticLoginSession" "${ROOTFS}/etc/gdm3/custom.conf"; then
        sudo sed -i "s/^AutomaticLoginSession.*/AutomaticLoginSession = ${TARGET_SESSION}/" "${ROOTFS}/etc/gdm3/custom.conf"
    elif sudo grep -q "^#AutomaticLoginSession" "${ROOTFS}/etc/gdm3/custom.conf"; then
        sudo sed -i "s/^#AutomaticLoginSession.*/AutomaticLoginSession = ${TARGET_SESSION}/" "${ROOTFS}/etc/gdm3/custom.conf"
    else
        sudo sed -i "/\[daemon\]/a AutomaticLoginSession = ${TARGET_SESSION}" "${ROOTFS}/etc/gdm3/custom.conf"
    fi
fi


REPO_ROOT="$(cd "${WORKSPACE}/.." && pwd)"

if [ -n "$PRODUCT_COPY_FILES" ]; then
    print_info "Copying product files (PRODUCT_COPY_FILES)..."
    for file_pair in $PRODUCT_COPY_FILES; do
        src=$(echo "$file_pair" | cut -d':' -f1)
        dest=$(echo "$file_pair" | cut -d':' -f2)
        
        resolved_src="$src"
        if [ ! -f "$resolved_src" ] && [ -f "${REPO_ROOT}/${src}" ]; then
            resolved_src="${REPO_ROOT}/${src}"
        fi

        if [ -f "$resolved_src" ]; then
            print_info "  Copying $resolved_src -> $dest"
            sudo mkdir -p "$(dirname "${ROOTFS}/${dest}")"
            sudo cp -p "$resolved_src" "${ROOTFS}/${dest}"
        else
            print_warn "Source file $src not found!"
        fi
    done
fi


# 3. Create a 6000MB disk image
print_info "Creating 6000MB Raw Image..."
truncate -s 6000M "$IMAGE"

# 4. Setup loop device with offset
LOOP_VAL=${LOOP_OFFSET:-1048576}
LABEL_VAL=${ROOTFS_LABEL:-ubuntu-${DEVICE}}

print_info "Formatting at offset ${LOOP_VAL}..."
sudo losetup -D
LOOP_DEV=$(sudo losetup -f --show -o ${LOOP_VAL} "$IMAGE")

# Format
sudo mkfs.ext4 -b 4096 -O ^metadata_csum,^64bit,^huge_file,^has_journal "$LOOP_DEV"
sudo e2label "$LOOP_DEV" "${LABEL_VAL}"

# 5. Copy files (using -x to stay on one filesystem)
print_info "Copying files into the disk image..."
mkdir -p mnt_tmp
sudo mount "$LOOP_DEV" mnt_tmp
sudo cp -ax "$ROOTFS"/. mnt_tmp/
sudo sync
sudo umount mnt_tmp
sudo losetup -d "$LOOP_DEV"

# Free page cache to prevent memory/swap exhaustion during sparse conversion
print_info "Freeing system page cache before sparse conversion..."
sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

# 6. Sparse conversion
print_info "Converting to Android Sparse image..."
img2simg "$IMAGE" "$SPARSE_IMAGE"

# Free page cache again to leave the host system clean
print_info "Freeing system page cache after sparse conversion..."
sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

print_success "ubuntu_sparse.img is ready at out/target/product/${DEVICE}/ubuntu_sparse.img"

