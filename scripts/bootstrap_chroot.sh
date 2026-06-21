#!/bin/bash
set -e

# Run from root of workspace
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

# Load config logger helpers
source "${SCRIPT_DIR}/load_config.sh" "$@"

ROOTFS="../rootfs"

if [ ! -d "$ROOTFS" ]; then
    print_error "No rootfs directory found! Please run 'm setup-rootfs' first."
    exit 1
fi

# Function to clean up mounts on exit or error
cleanup() {
    print_info "Cleaning up chroot mounts..."
    sudo umount -l "$ROOTFS/tmp" 2>/dev/null || true
    sudo umount -l "$ROOTFS/sys" 2>/dev/null || true
    sudo umount -l "$ROOTFS/proc" 2>/dev/null || true
    sudo umount -l "$ROOTFS/dev/pts" 2>/dev/null || true
    sudo umount -l "$ROOTFS/dev" 2>/dev/null || true
}
trap cleanup EXIT

print_info "Preparing virtual filesystems for chroot..."
# Mount system nodes
sudo mount --bind /dev "$ROOTFS/dev"
sudo mount --bind /dev/pts "$ROOTFS/dev/pts"
sudo mount -t proc proc "$ROOTFS/proc"
sudo mount -t sysfs sysfs "$ROOTFS/sys"
sudo mount -t tmpfs tmpfs "$ROOTFS/tmp"

# Temporarily copy DNS settings for internet access inside chroot
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# Create a setup script inside the chroot
CHROOT_SCRIPT="tmp/chroot_setup.sh"
cat << 'EOF' | sudo tee "$ROOTFS/$CHROOT_SCRIPT" > /dev/null
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "Updating repositories..."
apt-get update

echo "Installing essential packages..."
apt-get install -y \
    sudo \
    udev \
    systemd-sysv \
    network-manager \
    openssh-server \
    dbus \
    libpam-systemd \
    policykit-1 \
    alsa-utils \
    locales

echo "Installing graphics and Qt6 build environment..."
apt-get install -y \
    build-essential \
    cmake \
    git \
    pkg-config \
    libwayland-dev \
    qt6-base-dev \
    qt6-declarative-dev \
    qt6-wayland-dev \
    libqt6svg6-dev \
    liblayershellqtinterface-dev \
    gdm3

# Set locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Create default ubuntu user if not exists
if ! id -u ubuntu &>/dev/null; then
    echo "Creating ubuntu user..."
    useradd -m -s /bin/bash ubuntu
    echo "ubuntu:1234" | chpasswd
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-ubuntu
fi

# Add ubuntu user to essential groups
usermod -aG sudo,audio,video,input,render ubuntu

# Enable essential systemd services
systemctl enable NetworkManager
systemctl enable ssh
systemctl enable gdm

# Clean packages
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Chroot setup completed successfully!"
EOF

sudo chmod +x "$ROOTFS/$CHROOT_SCRIPT"

print_info "Entering chroot and running package installation..."
# Run script inside chroot
if ! sudo chroot "$ROOTFS" /bin/bash "/$CHROOT_SCRIPT"; then
    print_error "Chroot execution failed!"
    exit 1
fi

# Clean up setup script
sudo rm -f "$ROOTFS/$CHROOT_SCRIPT"

print_success "Base rootfs packages bootstrap completed successfully!"
