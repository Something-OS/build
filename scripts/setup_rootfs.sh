#!/bin/bash
set -e

# Run from root of workspace
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

# Load config logger helpers
source "${SCRIPT_DIR}/load_config.sh" "$@"

ROOTFS_URL="$1"
DEFAULT_URL="https://github.com/Something-OS/releases/releases/download/v1.0.0/ubuntu-base-rootfs.tar.gz"

if [ -z "$ROOTFS_URL" ]; then
    print_warn "No rootfs URL provided. Using default: $DEFAULT_URL"
    ROOTFS_URL="$DEFAULT_URL"
fi

ROOTFS_DIR="../rootfs"
ARCHIVE_NAME="../rootfs.tar.gz"

if [ -d "$ROOTFS_DIR" ] && [ "$(ls -A "$ROOTFS_DIR" 2>/dev/null)" ]; then
    print_warn "Directory '${ROOTFS_DIR}' already exists and is not empty."
    if [ -t 0 ]; then
        read -p "Do you want to overwrite it? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            print_info "Aborting setup. Local rootfs left untouched."
            exit 0
        fi
    else
        print_warn "Non-interactive environment detected. Skipping setup to avoid overwriting existing rootfs."
        exit 0
    fi
    print_info "Removing existing rootfs directory (requires sudo)..."
    sudo rm -rf "$ROOTFS_DIR"
fi

print_info "Creating clean rootfs directory..."
mkdir -p "$ROOTFS_DIR"

print_info "Downloading rootfs base from: ${ROOTFS_URL}..."
if ! wget --show-progress "$ROOTFS_URL" -O "$ARCHIVE_NAME"; then
    print_error "Failed to download rootfs. Please verify the URL."
    rm -f "$ARCHIVE_NAME"
    exit 1
fi

print_info "Extracting rootfs archive preserving system permissions (requires sudo)..."
sudo tar -xpf "$ARCHIVE_NAME" -C "$ROOTFS_DIR/"

print_info "Cleaning up temporary download archive..."
rm -f "$ARCHIVE_NAME"

print_success "Ubuntu rootfs base successfully set up at '${ROOTFS_DIR}'!"
