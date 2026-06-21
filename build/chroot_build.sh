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
