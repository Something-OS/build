# Something OS Build Environment Setup Script
# Usage:
#   source build/envsetup.sh
#   lunch fajita
#   m bootimg

# Get the top of the workspace
export BUILD_TOP="$(pwd)"

# ANSI Color Codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'


function croot() {
    cd "$BUILD_TOP"
}

function lunch() {
    local target="$1"
    local devices=()
    local dev_paths=()

    # Find all devices containing a BoardConfig.mk
    for config in $(find "$BUILD_TOP/device" -mindepth 3 -maxdepth 4 -name "BoardConfig.mk" 2>/dev/null); do
        local dev_dir=$(dirname "$config")
        local dev_name=$(basename "$dev_dir")
        devices+=("$dev_name")
        dev_paths+=("$dev_dir")
    done

    if [ ${#devices[@]} -eq 0 ]; then
        echo "ERROR: No devices found under device/ directory."
        return 1
    fi

    # If no target specified, show menu
    if [ -z "$target" ]; then
        echo "Lunch menu... pick a combo:"
        for i in "${!devices[@]}"; do
            echo "  $((i+1)). something_${devices[$i]}-userdebug"
        done
        echo -n "Which would you like? [1]: "
        read choice
        if [ -z "$choice" ]; then
            choice=1
        fi
        local idx=$((choice-1))
        if [ $idx -lt 0 ] || [ $idx -ge ${#devices[@]} ]; then
            echo "Invalid selection."
            return 1
        fi
        target="${devices[$idx]}"
    fi

    # Clean target name (e.g. something_fajita-userdebug -> fajita)
    local clean_device="$target"
    clean_device="${clean_device#something_}"
    clean_device="${clean_device%-userdebug}"
    clean_device="${clean_device%-user}"

    # Verify device exists
    local found=false
    for dev in "${devices[@]}"; do
        if [ "$dev" = "$clean_device" ]; then
            found=true
            break
        fi
    done

    if [ "$found" = "false" ]; then
        echo "ERROR: Device '$clean_device' is not supported."
        return 1
    fi

    export TARGET_DEVICE="$clean_device"
    export TARGET_PRODUCT="something_$clean_device"
    export OUT_DIR="$BUILD_TOP/out/target/product/$clean_device"

    # Add build tools to PATH
    if [[ ":$PATH:" != *":$BUILD_TOP/build/tools:"* ]]; then
        export PATH="$BUILD_TOP/build/tools:$PATH"
    fi

    echo -e "${CYAN}==========================================${NC}"
    echo -e "  Platform: Something OS"
    echo -e "  Target Product: ${GREEN}$TARGET_PRODUCT${NC}"
    echo -e "  Target Device: ${GREEN}$TARGET_DEVICE${NC}"
    echo -e "  Out Directory: ${PURPLE}$OUT_DIR${NC}"
    echo -e "${CYAN}==========================================${NC}"
}

function m() {
    if [ -z "$TARGET_DEVICE" ]; then
        echo "ERROR: No target device set. Please run 'lunch' first."
        return 1
    fi
    make -C "$BUILD_TOP" DEVICE="$TARGET_DEVICE" "$@"
}

echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}  Something OS Build Environment Loader${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "  The following commands are now available:"
echo -e "    - ${GREEN}lunch${NC}    : Select target device and configurations"
echo -e "    - ${GREEN}m${NC}        : Build target components
                 Available targets:
                   • ${YELLOW}all${NC}        : Build bootimg, desktop, and rootfs
                   • ${YELLOW}bootimg${NC}    : Compile bootloader ramdisk & kernel
                   • ${YELLOW}kernel${NC}     : Compile Linux kernel sources & DTBs
                   • ${YELLOW}desktop${NC}    : Compile AndroidShell chroot environment
                   • ${YELLOW}rootfs${NC}     : Package Ubuntu raw & sparse system images
                   • ${YELLOW}flash${NC}      : Flash boot.img to device via fastboot
                   • ${YELLOW}flash-all${NC}  : Flash boot & rootfs to device via fastboot
                   • ${YELLOW}recovery-zip${NC}: Package recovery flashable zip image
                   • ${YELLOW}deploy${NC}     : Pack & deploy UI build to physical device
                   • ${YELLOW}setup-rootfs${NC}: Download and extract base rootfs dynamically
                   • ${YELLOW}bootstrap-rootfs${NC}: Install build tools/libs inside chroot environment
                   • ${YELLOW}clean${NC}      : Remove compiled build outputs"
echo -e "    - ${GREEN}croot${NC}    : Jump back to the workspace root directory"
echo -e "${CYAN}=================================================${NC}"
echo -e "Run '${GREEN}lunch${NC}' to select a target device combo."
