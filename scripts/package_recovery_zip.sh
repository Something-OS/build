#!/bin/bash
set -e

# Run from build directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$WORKSPACE"

source "${SCRIPT_DIR}/load_config.sh" "$@"

show_target_banner "Packaging Recovery-Flashable ZIP"

OUT_DIR="$(mkdir -p ../out/target/product/${DEVICE} && cd ../out/target/product/${DEVICE} && pwd)"
BOOT_IMG="${OUT_DIR}/boot.img"
RAW_IMG="${OUT_DIR}/ubuntu.img"
ZIP_OUT="${OUT_DIR}/something_os_${DEVICE}_recovery.zip"

if [ ! -f "$BOOT_IMG" ]; then
    print_error "Boot image not found at $BOOT_IMG! Run 'm bootimg' first."
    exit 1
fi

if [ ! -f "$RAW_IMG" ]; then
    print_error "Raw system image not found at $RAW_IMG! Run 'm rootfs' first."
    exit 1
fi

print_info "Creating temporary recovery zip staging directory..."
STAGING_DIR="${OUT_DIR}/zip_staging"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/META-INF/com/google/android"

# Copy images to staging directory
print_info "Copying boot and system images..."
cp "$BOOT_IMG" "$STAGING_DIR/"
cp "$RAW_IMG" "$STAGING_DIR/"

# Write update-binary shell script
print_info "Creating installer script..."
cat << 'EOF' > "$STAGING_DIR/META-INF/com/google/android/update-binary"
#!/sbin/sh
# Something OS Recovery Installer Script

OUTFD=$2
ZIPPATH=$3

ui_print() {
    echo "ui_print $1" >&$OUTFD
    echo "ui_print" >&$OUTFD
}

ui_print "=========================================="
ui_print "       Something OS Installer"
ui_print "=========================================="
ui_print "Target Device: OnePlus 6T (fajita)"
ui_print "=========================================="

# Find active slot
SLOT=$(getprop ro.boot.slot_suffix)
if [ -z "$SLOT" ]; then
    # Fallback to checking cmdline if prop is empty
    SLOT=$(cat /proc/cmdline | tr ' ' '\n' | grep androidboot.slot_suffix | cut -d= -f2)
fi

if [ -n "$SLOT" ]; then
    ui_print "Detected active slot: $SLOT"
    BOOT_DEV="/dev/block/by-name/boot$SLOT"
else
    ui_print "No active slot detected. Flashing to boot_a and boot_b..."
    BOOT_DEV="/dev/block/by-name/boot_a"
    BOOT_DEV_B="/dev/block/by-name/boot_b"
fi

USERDATA_DEV="/dev/block/by-name/userdata"

# Check if target devices exist
if [ ! -b "$BOOT_DEV" ]; then
    ui_print "Error: Boot device $BOOT_DEV not found!"
    exit 1
fi

if [ ! -b "$USERDATA_DEV" ]; then
    ui_print "Error: Userdata device $USERDATA_DEV not found!"
    exit 1
fi

# Extract and flash boot image
ui_print "Flashing boot image..."
unzip -p "$ZIPPATH" boot.img > "$BOOT_DEV"
if [ $? -ne 0 ]; then
    ui_print "Error flashing boot image!"
    exit 1
fi

if [ -n "$BOOT_DEV_B" ] && [ -b "$BOOT_DEV_B" ]; then
    ui_print "Flashing boot image to slot B..."
    unzip -p "$ZIPPATH" boot.img > "$BOOT_DEV_B"
fi

# Extract and flash rootfs
ui_print "Flashing system image to userdata..."
ui_print "This will take a few minutes (streaming decompress)..."
unzip -p "$ZIPPATH" ubuntu.img | dd of="$USERDATA_DEV" bs=4M status=none
if [ $? -ne 0 ]; then
    ui_print "Error flashing system image!"
    exit 1
fi

ui_print "=========================================="
ui_print "  Installation completed successfully!"
ui_print "  Reboot your device to start Something OS."
ui_print "=========================================="
exit 0
EOF

chmod +x "$STAGING_DIR/META-INF/com/google/android/update-binary"

# Touch dummy updater-script as some recoveries require it to exist
touch "$STAGING_DIR/META-INF/com/google/android/updater-script"

print_info "Zipping recovery package (this might take a moment)..."
rm -f "$ZIP_OUT"
(cd "$STAGING_DIR" && zip -r -1 "$ZIP_OUT" .)

print_success "Recovery flashable zip is ready at: $ZIP_OUT"
