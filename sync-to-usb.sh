#!/bin/bash
# sync-to-usb.sh — Copy autoconfig files + preseed from repo to OMV installer USB
# Usage: bash sync-to-usb.sh /mnt/usb
set -euo pipefail

USB="${1:?Usage: $0 <usb-mount-point>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify USB has OMV installer structure
if [ ! -d "$USB/install" ]; then
    echo "ERROR: $USB/install/ not found. Is this the OMV installer USB?"
    exit 1
fi

# Create postinstall dir if needed
mkdir -p "$USB/postinstall"

# Copy autoconfig files
echo "Copying network autoconfig files..."
cp "${SCRIPT_DIR}/config/nas-net-autoconfig.sh" "${USB}/postinstall/"
cp "${SCRIPT_DIR}/config/nas-net-autoconfig.service" "${USB}/postinstall/"
cp "${SCRIPT_DIR}/config/wifi.conf" "${USB}/postinstall/"
if ! grep -q 'CHANGE_ME' "${SCRIPT_DIR}/config/wifi.conf"; then
    echo "  WARNING: wifi.conf contains real credentials — USB drive is now sensitive media"
fi

# Copy preseed to USB root
echo "Copying preseed.cfg to USB root..."
cp "${SCRIPT_DIR}/config/preseed.cfg" "${USB}/preseed.cfg"

# Copy quickstart if it exists
if [ -f "${SCRIPT_DIR}/config/quickstart.sh" ]; then
    cp "${SCRIPT_DIR}/config/quickstart.sh" "${USB}/postinstall/"
fi

echo ""
echo "Done. Files synced to USB."
echo ""
echo "MANUAL STEP REMAINING:"
echo "  Update isolinux/install.cfg boot parameter:"
echo "    Change: file=/cdrom/install/preseed.cfg"
echo "    To:     file=/cdrom/preseed.cfg auto=true"
