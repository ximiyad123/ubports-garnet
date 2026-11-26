#!/bin/bash
set -e

# ==========================================
# UBports Garnet Fastboot Installer
# ==========================================

IMAGE_DIR="images"

VENDOR_IMG="$IMAGE_DIR/vendor.img"
VENDOR_URL="https://downloads.sourceforge.net/project/ubports-garnet/vendor/vendor-ubports-20260822.img"

# Trusted SHA-256 for vendor.img
VENDOR_SHA256="7040abe672844a4e80fba1597951044574334a57a362fdf66f2d879e9a30b9cd"

echo "=========================================="
echo " UBports Garnet Fastboot Installer"
echo " For Device: Redmi Note 13 Pro 5G / Poco X6"
echo " Codenames: garnetp / garnet / XIG05"
echo " Credits: ximiyad123"
echo "=========================================="
echo ""

# ==========================================
# Install / Update selection
# ==========================================

read -p "Would you like to (I)nstall Ubuntu Touch or (U)pdate Ubuntu Touch? [I/U]: " action

case "$action" in
    i|I)
        echo "Selected: Install Ubuntu Touch"
        FRESH_INSTALL=true
        ALLOW_WIPE=true
        ;;
    u|U)
        echo "Selected: Update Ubuntu Touch"
        FRESH_INSTALL=false
        ALLOW_WIPE=true
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

echo ""

# ==========================================
# Required commands
# ==========================================

for cmd in fastboot sha256sum grep awk sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is required but was not found."
        exit 1
    fi
done

mkdir -p "$IMAGE_DIR"

# ==========================================
# Download vendor
# ==========================================

download_vendor() {
    echo "Downloading vendor image to $VENDOR_IMG..."
    echo ""

    rm -f "$VENDOR_IMG"

    if command -v wget >/dev/null 2>&1; then
        wget -O "$VENDOR_IMG" "$VENDOR_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -L --fail -o "$VENDOR_IMG" "$VENDOR_URL"
    else
        echo "Error: Neither wget nor curl was found."
        exit 1
    fi

    if [ ! -s "$VENDOR_IMG" ]; then
        echo "Error: vendor.img download failed or is empty."
        exit 1
    fi

    echo ""
    echo "Download complete."
    echo ""
}

# ==========================================
# Normal SHA-256 verification
# ==========================================

verify_sha256() {
    local file="$1"
    local checksum_file="$2"

    local expected
    local actual
    local hash_output

    if [ ! -f "$file" ]; then
        echo "Error: Missing file:"
        echo "  $file"
        exit 1
    fi

    if [ ! -f "$checksum_file" ]; then
        echo "Error: Missing checksum file:"
        echo "  $checksum_file"
        exit 1
    fi

    echo "Verifying $(basename "$file")..."

    # Read the expected checksum directly from the checksum file.
    expected="$(awk 'NF {print $1; exit}' "$checksum_file")"

    if [ -z "$expected" ]; then
        echo ""
        echo "Error: Checksum file is empty or invalid:"
        echo "  $checksum_file"
        exit 1
    fi

    # Calculate the checksum using the ACTUAL image path
    # (the checksum file only contains the bare filename).
    if ! hash_output="$(sha256sum "$file" 2>&1)"; then
        echo ""
        echo "=========================================="
        echo " ERROR: SHA-256 calculation failed"
        echo "=========================================="
        echo ""
        echo "File:"
        echo "  $file"
        echo ""
        echo "$hash_output"
        echo ""
        exit 1
    fi

    actual="${hash_output%% *}"

    if [ "$actual" = "$expected" ]; then
        echo "SHA-256 OK."
        echo ""
        return 0
    fi

    echo ""
    echo "=========================================="
    echo " WARNING: SHA-256 mismatch"
    echo "=========================================="
    echo ""
    echo "File:"
    echo "  $file"
    echo ""

    echo "Expected:"
    echo "  $expected"
    echo ""

    echo "Actual:"
    echo "  $actual"
    echo ""

    read -p "Continue anyway? (y/N): " choice

    case "$choice" in
        y|Y)
            echo ""
            echo "WARNING: Continuing with an unverified file."
            echo ""
            ;;
        *)
            echo ""
            echo "Cancelled."
            exit 1
            ;;
    esac
}

# ==========================================
# Vendor SHA-256 verification
# ==========================================

verify_vendor_sha256() {
    local actual
    local hash_output

    while true; do

        if ! hash_output="$(sha256sum "$VENDOR_IMG" 2>&1)"; then
            echo ""
            echo "=========================================="
            echo " ERROR: Could not calculate vendor SHA-256"
            echo "=========================================="
            echo ""
            echo "$hash_output"
            echo ""
            exit 1
        fi

        actual="${hash_output%% *}"

        if [ "$actual" = "$VENDOR_SHA256" ]; then
            echo "Vendor SHA-256 OK."
            echo ""
            return 0
        fi

        echo ""
        echo "=========================================="
        echo " WARNING: vendor.img SHA-256 mismatch!"
        echo "=========================================="
        echo ""

        echo "Expected:"
        echo "  $VENDOR_SHA256"
        echo ""

        echo "Actual:"
        echo "  $actual"
        echo ""

        echo "What would you like to do?"
        echo ""
        echo "  (R)edownload vendor.img"
        echo "  (F)lash it anyway"
        echo "  (C)ancel"
        echo ""

        read -p "Choose [R/F/C]: " vendor_choice

        case "$vendor_choice" in
            r|R)
                echo ""
                download_vendor
                ;;

            f|F)
                echo ""
                echo "WARNING: Flashing vendor.img despite SHA-256 mismatch."
                echo ""
                return 0
                ;;

            c|C)
                echo ""
                echo "Cancelled."
                exit 1
                ;;

            *)
                echo ""
                echo "Invalid choice."
                echo ""
                ;;
        esac
    done
}

# ==========================================
# Vendor download + verification
# ==========================================

if [ ! -f "$VENDOR_IMG" ]; then
    download_vendor
fi

verify_vendor_sha256

# ==========================================
# Fastboot helpers
# ==========================================

get_userspace() {
    fastboot getvar is-userspace 2>&1 |
        grep -oE 'is-userspace:[[:space:]]*(yes|no)' |
        awk -F: '{gsub(/[[:space:]]/, "", $2); print $2}' |
        tail -n 1 || true
}

wait_for_fastboot() {
    echo "Waiting for fastboot device..."

    for i in $(seq 1 60); do
        if fastboot devices 2>/dev/null | grep -q '[^[:space:]]'; then
            echo "Fastboot device detected."
            return 0
        fi

        sleep 1
    done

    echo "Error: Device did not return to fastboot."
    exit 1
}

ensure_fastbootd() {
    local userspace

    userspace="$(get_userspace)"

    if [ "$userspace" = "yes" ]; then
        echo "Device is already in fastbootd."
        return 0
    fi

    echo "Device is in bootloader."
    echo "Rebooting into fastbootd..."

    fastboot reboot fastboot

    wait_for_fastboot

    userspace="$(get_userspace)"

    if [ "$userspace" != "yes" ]; then
        echo "Error: Could not confirm fastbootd mode."
        exit 1
    fi

    echo "Now in fastbootd."
}

ensure_bootloader() {
    local userspace

    userspace="$(get_userspace)"

    if [ "$userspace" != "yes" ]; then
        echo "Device is already in bootloader."
        return 0
    fi

    echo "Device is in fastbootd."
    echo "Rebooting into bootloader..."

    fastboot reboot bootloader

    wait_for_fastboot

    userspace="$(get_userspace)"

    if [ "$userspace" = "yes" ]; then
        echo "Error: Still in fastbootd after reboot."
        exit 1
    fi

    echo "Now in bootloader."
}

# ==========================================
# Device detection
# ==========================================

echo "Checking fastboot mode..."

# For wipe-super and -w, we need to be in bootloader
echo "Ensuring bootloader mode..."
ensure_bootloader

echo ""

echo "Checking device codename..."

PRODUCT="$(
    fastboot getvar product 2>&1 |
        grep -oE 'product:[[:space:]]*[A-Za-z0-9_-]+' |
        awk -F: '{gsub(/[[:space:]]/, "", $2); print $2}' |
        tail -n 1 || true
)"

if [ -z "$PRODUCT" ]; then
    PRODUCT="$(
        fastboot getvar partition-type:product 2>&1 |
            grep -oE 'partition-type:product:[[:space:]]*[A-Za-z0-9_-]+' |
            awk -F: '{print $3}' |
            tail -n 1 || true
    )"
fi

case "$PRODUCT" in
    garnetp|garnet|XIG05|xig05)
        echo "Detected supported device: $PRODUCT"
        ;;

    *)
        echo "Warning: Unrecognized device codename '$PRODUCT'."
        echo ""
        echo "This script targets:"
        echo "  garnetp / garnet / XIG05"
        echo "  Redmi Note 13 Pro 5G / Poco X6"
        echo ""

        read -p "Continue anyway? (y/N): " forcechoice

        case "$forcechoice" in
            y|Y)
                echo "Continuing at your own risk..."
                ;;

            *)
                echo "Aborting."
                exit 1
                ;;
        esac
        ;;
esac

echo ""

# ==========================================
# Detect current slot
# ==========================================

CURRENT_SLOT="$(
    fastboot getvar current-slot 2>&1 |
        grep -oE 'current-slot:[[:space:]]*[ab]' |
        awk -F: '{gsub(/[[:space:]]/, "", $2); print $2}' |
        tail -n 1 || true
)"

if [ -z "$CURRENT_SLOT" ]; then
    echo "Error: Unable to detect current slot."
    exit 1
fi

echo "Current slot: $CURRENT_SLOT"
echo ""

# ==========================================
# Verify image files
# ==========================================

echo "=========================================="
echo " Checking image files"
echo "=========================================="
echo ""

verify_sha256 \
    "$IMAGE_DIR/super_empty.img" \
    "$IMAGE_DIR/super_empty.sha256"

verify_sha256 \
    "$IMAGE_DIR/odm.img" \
    "$IMAGE_DIR/odm.sha256"

verify_sha256 \
    "$IMAGE_DIR/system.img" \
    "$IMAGE_DIR/system.sha256"

verify_sha256 \
    "$IMAGE_DIR/boot.img" \
    "$IMAGE_DIR/boot.sha256"

if [ "$FRESH_INSTALL" = false ]; then
    verify_sha256 \
        "$IMAGE_DIR/boot_stock.img" \
        "$IMAGE_DIR/boot_stock.sha256"
fi

if [ -f "$IMAGE_DIR/dtbo.img" ]; then
    verify_sha256 \
        "$IMAGE_DIR/dtbo.img" \
        "$IMAGE_DIR/dtbo.sha256"
fi

if [ -f "$IMAGE_DIR/vendor_boot.img" ]; then
    verify_sha256 \
        "$IMAGE_DIR/vendor_boot.img" \
        "$IMAGE_DIR/vendor_boot.sha256"
fi

if [ -f "$IMAGE_DIR/vendor_dlkm.img" ]; then
    verify_sha256 \
        "$IMAGE_DIR/vendor_dlkm.img" \
        "$IMAGE_DIR/vendor_dlkm.sha256"
fi

echo "All image checks completed."
echo ""

# ==========================================
# Wipe super helper
# ==========================================

wipe_super() {
    echo ""
    echo "=========================================="
    echo " Wiping super"
    echo "=========================================="
    echo ""

    if ! fastboot wipe-super "$IMAGE_DIR/super_empty.img"; then
        echo ""
        echo "ERROR: wipe-super failed."
        return 1
    fi

    echo ""
    echo "super wiped successfully."
    return 0
}

# ==========================================
# Detect size/full partition errors
# ==========================================

is_size_error() {
    local output="$1"
    local pattern='remote:.*(space|size|full)|partition.*(full|too large)|not enough space|insufficient space|size.*too large|image.*too large|file.*too large|super.*(full|space)|logical partition.*(full|space)|no space left|空间不足|logical.*exceeds.*container|opposing.*aosp'

    echo "$output" | grep -qiE -- "$pattern"
}

# ==========================================
# Flash partition with size-error handling
# ==========================================

flash_partition() {
    local partition="$1"
    local image="$2"

    local output
    local result
    local answer

    echo ""
    echo "------------------------------------------"
    echo "Flashing:"
    echo "  File:      $image"
    echo "  Partition: $partition"
    echo "------------------------------------------"

    set +e
    output="$(fastboot flash "$partition" "$image" 2>&1)"
    result=$?
    set -e

    echo "$output"

    if [ "$result" -eq 0 ]; then
        echo ""
        return 0
    fi

    if ! is_size_error "$output"; then
        echo ""
        echo "Failed to flash $image."
        echo "The error does not appear to be a partition-size problem."
        echo ""
        return 1
    fi

    echo ""
    echo "=========================================="
    echo " Flash failed because of a possible size"
    echo " / dynamic-partition capacity problem."
    echo "=========================================="
    echo ""
    echo "Failed to flash $image."
    echo ""

    echo 'If the error is "size too big" or "partition is full",'
    echo "would you like to (W)ipe super or (C)ancel?"
    echo ""

    read -p "[W/C]: " answer

    case "$answer" in
        w|W)

            echo ""
            echo "Wiping super..."

            if ! wipe_super; then
                return 1
            fi

            echo ""
            echo "Retrying $partition..."

            set +e
            fastboot flash "$partition" "$image"
            result=$?
            set -e

            if [ "$result" -ne 0 ]; then
                echo ""
                echo "Retry failed."
                return 1
            fi

            echo ""
            echo "Retry succeeded."
            return 0
            ;;

        c|C|*)
            echo ""
            echo "Cancelled."
            return 1
            ;;
    esac
}

# ==========================================
# Optional / required image helper
# ==========================================

flash_image() {
    local partition="$1"
    local file_name="$2"
    local suffix="$3"
    local required="$4"

    local file_path="$IMAGE_DIR/$file_name"
    local target="${partition}${suffix}"

    if [ -f "$file_path" ]; then

        if ! flash_partition "$target" "$file_path"; then
            echo "Aborting: flashing $target failed."
            exit 1
        fi

    else

        if [ "$required" = "true" ]; then
            echo ""
            echo "Error: Required image missing:"
            echo "  $file_path"
            exit 1
        else
            echo "Skipping optional image:"
            echo "  $file_path"
            echo ""
        fi

    fi
}

# ==========================================
# INSTALL / UPDATE (same flow)
#
# Update = Install, except it:
#   - flashes stock boot to the active slot first
#   - never wipes or asks about userdata
# ==========================================

if [ "$FRESH_INSTALL" = true ]; then
    echo "=========================================="
    echo " Fresh Ubuntu Touch Installation"
    echo "=========================================="
else
    echo "=========================================="
    echo " Ubuntu Touch Update"
    echo "=========================================="
fi
echo ""

echo "This will recreate the dynamic partition"
echo "layout using super_empty.img."
echo ""

read -p "Continue? (y/N): " superchoice

case "$superchoice" in
    y|Y)
        ;;
    *)
        echo "Aborting."
        exit 1
        ;;
esac

echo ""

# --------------------------------------
# Update only: flash stock boot
# --------------------------------------

if [ "$FRESH_INSTALL" = false ]; then

    echo "=========================================="
    echo " Flashing stock boot to boot_$CURRENT_SLOT"
    echo "=========================================="
    echo ""

    fastboot flash "boot_$CURRENT_SLOT" "$IMAGE_DIR/boot_stock.img"

    echo ""

fi

# --------------------------------------
# Wipe super (in bootloader)
# --------------------------------------

wipe_super

echo ""

# --------------------------------------
# Switch to fastbootd for flashing
# --------------------------------------

echo "Switching to fastbootd for flashing..."

fastboot reboot fastboot

wait_for_fastboot

ensure_fastbootd

echo ""

# --------------------------------------
# Optional userdata wipe (install only)
# --------------------------------------

if [ "$FRESH_INSTALL" = true ]; then

    echo "WARNING: This will erase all user data."
    echo ""

    read -p "Wipe userdata now? (y/N): " wipechoice

    case "$wipechoice" in
        y|Y)

            echo ""
            echo "Rebooting to bootloader..."

            fastboot reboot bootloader

            wait_for_fastboot

            echo "Wiping userdata and metadata..."

            fastboot -w

            echo ""
            echo "Rebooting back to bootloader..."

            fastboot reboot bootloader

            wait_for_fastboot

            echo ""
            echo "Rebooting back into fastbootd..."

            fastboot reboot fastboot

            wait_for_fastboot

            ensure_fastbootd

            echo ""

            ;;

        *)
            echo "Skipping data wipe."
            echo ""
            ;;
    esac

fi

# --------------------------------------
# Flash active slot only
# --------------------------------------

ACTIVE_SUFFIX="_$CURRENT_SLOT"

echo "=========================================="
echo " Flashing slot $CURRENT_SLOT (active)"
echo "=========================================="
echo ""

flash_image "dtbo" \
    "dtbo.img" "$ACTIVE_SUFFIX" "false"

flash_image "boot" \
    "boot.img" "$ACTIVE_SUFFIX" "true"

flash_image "odm" \
    "odm.img" "$ACTIVE_SUFFIX" "true"

flash_image "vendor_boot" \
    "vendor_boot.img" "$ACTIVE_SUFFIX" "false"

flash_image "vendor_dlkm" \
    "vendor_dlkm.img" "$ACTIVE_SUFFIX" "false"

flash_image "vendor" \
    "vendor.img" "$ACTIVE_SUFFIX" "true"

flash_image "system" \
    "system.img" "$ACTIVE_SUFFIX" "true"

echo ""
echo "=========================================="
echo " Active slot $CURRENT_SLOT has been installed"
echo "=========================================="
echo ""

echo "Keeping active slot: $CURRENT_SLOT"

# ==========================================
# Finish
# ==========================================

echo ""
echo "=========================================="
echo " Ubuntu Touch installation/update complete"
echo "=========================================="
echo ""
echo "Credits: ximiyad123"
echo ""

read -p "Reboot device into Ubuntu Touch now? (y/N): " choice

case "$choice" in
    y|Y)
        echo ""
        echo "Rebooting..."
        fastboot reboot
        ;;

    *)
        echo ""
        echo "Finished."
        echo "Reboot manually when ready."
        ;;
esac
