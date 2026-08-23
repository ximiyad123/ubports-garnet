#!/bin/bash
set -e

# Configurable variables
IMAGE_DIR="images"
VENDOR_URL="https://downloads.sourceforge.net/project/ubports-garnet/vendor/vendor-ubports-20260822.img"

echo "=========================================="
echo " UBports Garnet Fastboot Installer        "
echo " For Device: Redmi Note 13 Pro 5G / Poco X6 "
echo " Codenames: garnetp / garnet / XIG05       "
echo " Credits: ximiyad123                      "
echo "=========================================="
echo ""

# Ensure images directory exists
mkdir -p "$IMAGE_DIR"

# Download missing vendor image if needed
VENDOR_IMG="$IMAGE_DIR/vendor.img"
if [ ! -f "$VENDOR_IMG" ]; then
    echo "Downloading vendor image to $VENDOR_IMG..."
    if command -v wget >/dev/null 2>&1; then
        wget -O "$VENDOR_IMG" "$VENDOR_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "$VENDOR_IMG" "$VENDOR_URL"
    else
        echo "Error: Neither wget nor curl was found. Please install one to download vendor.img."
        exit 1
    fi
    echo "Download complete."
    echo ""
fi

# Detect bootloader vs fastbootd
echo "Checking fastboot mode..."
IS_USERSPACE=$(fastboot getvar is-userspace 2>&1 | grep -oP 'is-userspace:\s*\K\w+' || true)
if [ "$IS_USERSPACE" = "yes" ]; then
    echo "Device is in fastbootd. Continuing..."
else
    echo "Device is in bootloader. Rebooting into fastbootd..."
    fastboot reboot fastboot
    echo "Waiting for device to come back in fastbootd..."
    sleep 5
    IS_USERSPACE=$(fastboot getvar is-userspace 2>&1 | grep -oP 'is-userspace:\s*\K\w+' || true)
    if [ "$IS_USERSPACE" = "yes" ]; then
        echo "Now in fastbootd. Continuing..."
    else
        echo "Error: Could not confirm fastbootd mode. Aborting."
        exit 1
    fi
fi
echo ""

# Detect device codename and verify it's a supported target
echo "Checking device codename..."
PRODUCT=$(fastboot getvar product 2>&1 | grep -oP 'product:\s*\K\S+' || true)
if [ -z "$PRODUCT" ]; then
    PRODUCT=$(fastboot getvar partition-type:product 2>&1 | grep -oP 'partition-type:product:\s*\K\S+' || true)
fi

case "$PRODUCT" in
    garnetp|garnet|XIG05|xig05)
        echo "Detected supported device: $PRODUCT"
        ;;
    *)
        echo "Warning: Unrecognized device codename '$PRODUCT'."
        echo "This script targets garnetp / garnet / XIG05 (Redmi Note 13 Pro 5G / Poco X6)."
        read -p "Continue anyway? (y/N): " forcechoice
        case "$forcechoice" in
            y|Y ) echo "Continuing at your own risk..." ;;
            * ) echo "Aborting."; exit 1 ;;
        esac
        ;;
esac
echo ""

# Detect active slot suffix (_a or _b)
SLOT=$(fastboot getvar current-slot 2>&1 | grep -oP 'current-slot:\s*\K[a-b]')
if [ -n "$SLOT" ]; then
    SLOT_SUFFIX="_$SLOT"
    echo "Detected active slot: $SLOT"
else
    SLOT_SUFFIX=""
    echo "Warning: Unable to detect active slot suffix. Proceeding without slot suffix..."
fi

# Free product logical partition and erase vendor/mi_ext on the CURRENT slot
echo ""
echo "Freeing product$SLOT_SUFFIX and mi_ext$SLOT_SUFFIX from super, and erasing vendor$SLOT_SUFFIX..."
fastboot delete-logical-partition "product$SLOT_SUFFIX" 2>/dev/null || true
fastboot erase "vendor$SLOT_SUFFIX" 2>/dev/null || true
fastboot erase "mi_ext$SLOT_SUFFIX" 2>/dev/null || true

# Wipe userdata and metadata via bootloader
echo ""
echo "WARNING: This will erase all user data on the device."
echo "NOTE: If you are updating Ubuntu Touch, proceed to select No."
read -p "Wipe userdata now? (y/N): " wipechoice
case "$wipechoice" in
    y|Y )
        echo "Rebooting to bootloader to perform data wipe..."
        fastboot reboot bootloader
        sleep 5

        echo "Wiping userdata and metadata via fastboot -w..."
        fastboot -w

        echo "Rebooting back into fastbootd..."
        fastboot reboot fastboot
        sleep 5
        ;;
    * )
        echo "Skipping data wipe."
        ;;
esac
echo ""

# Helper function to flash images safely
flash_image() {
    local partition="$1"
    local file_path="$IMAGE_DIR/$2"
    local required="$3"

    if [ -f "$file_path" ]; then
        echo "Flashing $file_path to ${partition}${SLOT_SUFFIX}..."
        fastboot flash "${partition}${SLOT_SUFFIX}" "$file_path"
    else
        if [ "$required" = "true" ]; then
            echo "Error: $file_path not found in $IMAGE_DIR/ directory!"
            exit 1
        else
            echo "Skipping optional partition $partition ($file_path not found)..."
        fi
    fi
}

# Flashing partitions
echo "Starting flash sequence..."
flash_image "dtbo" "dtbo.img" "false"
flash_image "boot" "boot.img" "true"
flash_image "odm" "odm.img" "true"
flash_image "vendor_boot" "vendor_boot.img" "false"
flash_image "vendor_dlkm" "vendor_dlkm.img" "false"
flash_image "vendor" "vendor.img" "true"
flash_image "system" "system.img" "true"

echo ""
echo "=========================================="
echo " Installation Complete!                  "
echo " Credits: ximiyad123                      "
echo "=========================================="
echo ""
read -p "Reboot device into Ubuntu Touch now? (y/N): " choice
case "$choice" in
    y|Y ) fastboot reboot ;;
    * ) echo "Finished. Reboot manually when ready." ;;
esac
