#!/bin/bash
set -e

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE"

DEVICE="${1:-fajita}"
OUT_DIR="$(mkdir -p ../out/target/product/${DEVICE} && cd ../out/target/product/${DEVICE} && pwd)"
SPARSE_IMAGE="${OUT_DIR}/ubuntu_sparse.img"
RAW_IMAGE="${OUT_DIR}/ubuntu.img"
PARTITION="userdata"

if [ -f "$SPARSE_IMAGE" ]; then
    IMAGE="$SPARSE_IMAGE"
    IMAGE_TYPE="Android sparse image"
elif [ -f "$RAW_IMAGE" ]; then
    IMAGE="$RAW_IMAGE"
    IMAGE_TYPE="raw ext4 image"
else
    echo "ERROR: Neither ubuntu_sparse.img nor ubuntu.img found in ${OUT_DIR}"
    exit 1
fi

echo "[*] Flashing $IMAGE_TYPE to $PARTITION partition for ${DEVICE}..."
fastboot flash "$PARTITION" "$IMAGE"
echo "[✓] Done!"
