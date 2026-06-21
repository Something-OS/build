#!/bin/bash
set -e

# Run from build directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

show_target_banner "Building Desktop Shell"

ROOTFS_DIR="../rootfs"
SRC_DIR="../androidshell"
CHROOT_SRC="/opt/desktop_build"

# Define cleanup function for exit trap
cleanup() {
    print_info "Cleaning up chroot mounts and files..."
    sudo umount -l "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    sudo umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
    sudo umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
    sudo umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
    sudo rm -f "${ROOTFS_DIR}/tmp/chroot_build.sh" 2>/dev/null || true
    sudo rm -rf "${ROOTFS_DIR}${CHROOT_SRC}" 2>/dev/null || true
}
trap cleanup EXIT

# Clean up any leftover mounts/files from previous runs before starting
cleanup

print_info "Setting up ARM64 chroot environment..."

# Ensure qemu static binary is present in the rootfs
if [ ! -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static" ]; then
    sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_DIR}/usr/bin/"
fi

# Copy source code into rootfs for compilation
print_info "Copying androidshell source to chroot..."
sudo rm -rf "${ROOTFS_DIR}${CHROOT_SRC}"
sudo mkdir -p "${ROOTFS_DIR}${CHROOT_SRC}"
sudo cp -r ${SRC_DIR}/* "${ROOTFS_DIR}${CHROOT_SRC}/"

print_info "Entering chroot environment to compile desktop shell..."

# Create a build script to run inside the chroot
mkdir -p build
cat << 'EOF' > build/chroot_build.sh
#!/bin/bash
set -e
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export DEBIAN_FRONTEND=noninteractive

BLUE='\033[0;34m'
NC='\033[0m'

cd /opt/desktop_build

# Ensure build directory is clean
rm -rf build && mkdir build && cd build

echo -e "${BLUE}[Something OS]${NC} Running CMake inside chroot..."
cmake ..
echo -e "${BLUE}[Something OS]${NC} Running Make inside chroot..."
make -j$(nproc)

# Install the binary to the correct location in the rootfs
mkdir -p /home/ubuntu/desktop-environment/build
cp AndroidShell /home/ubuntu/desktop-environment/build/
chown -R 1000:1000 /home/ubuntu/desktop-environment

# Copy QML and assets to the user's directory
cp -r ../qml /home/ubuntu/desktop-environment/
for ext in svg ttf otf png; do
    cp ../*.$ext /home/ubuntu/desktop-environment/ 2>/dev/null || true
done

# Install the session launcher script
cp ../androidshell-session /home/ubuntu/desktop-environment/androidshell-session
chmod +x /home/ubuntu/desktop-environment/androidshell-session

# Install switching scripts to /usr/local/bin/
cp ../switch-to-androidshell /usr/local/bin/switch-to-androidshell
cp ../switch-to-phosh /usr/local/bin/switch-to-phosh
chmod +x /usr/local/bin/switch-to-androidshell /usr/local/bin/switch-to-phosh

chown -R 1000:1000 /home/ubuntu/desktop-environment
EOF

chmod +x build/chroot_build.sh
sudo cp build/chroot_build.sh "${ROOTFS_DIR}/tmp/"

# Mount necessary filesystems
sudo mount -t proc proc "${ROOTFS_DIR}/proc"
sudo mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"

# Execute the build inside chroot
sudo chroot "${ROOTFS_DIR}" /bin/bash /tmp/chroot_build.sh

print_success "Desktop shell compiled and installed successfully inside chroot!"

