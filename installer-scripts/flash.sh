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
        ;;
    u|U)
        echo "Selected: Update Ubuntu Touch"
        FRESH_INSTALL=false
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

    # Calculate the checksum using the ACTUAL image path.
    #
    # Do not use:
    #   sha256sum -c "$checksum_file"
    #
    # because the checksum file normally contains only:
    #   filename.img
    #
    # and the image itself is inside $IMAGE_DIR.
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

# ==========================================
# Device detection
# ==========================================

echo "Checking fastboot mode..."

ensure_fastbootd

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
# Determine target slot
# ==========================================

if [ "$FRESH_INSTALL" = true ]; then

    echo "Fresh installation will flash BOTH slots."
    echo ""

else

    if [ "$CURRENT_SLOT" = "a" ]; then
        TARGET_SLOT="b"
    else
        TARGET_SLOT="a"
    fi

    CURRENT_SUFFIX="_$CURRENT_SLOT"
    TARGET_SUFFIX="_$TARGET_SLOT"

    echo "Current slot: $CURRENT_SLOT"
    echo "Update slot:  $TARGET_SLOT"
    echo ""

fi

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

    echo "$output" | grep -qiE \
        'partition.*(full|too large)|'\
        'not enough space|'\
        'insufficient space|'\
        'size.*too large|'\
        'image.*too large|'\
        'file.*too large|'\
        'super.*(full|space)|'\
        'logical partition.*(full|space)|'\
        'no space left'
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

        flash_partition "$target" "$file_path"

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
# FRESH INSTALL
# ==========================================

if [ "$FRESH_INSTALL" = true ]; then

    echo "=========================================="
    echo " Fresh Ubuntu Touch Installation"
    echo "=========================================="
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
    # Wipe super
    # --------------------------------------

    wipe_super

    echo ""

    # --------------------------------------
    # Optional userdata wipe
    # --------------------------------------

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

    # --------------------------------------
    # Flash slot A
    # --------------------------------------

    echo "=========================================="
    echo " Flashing slot A"
    echo "=========================================="
    echo ""

    flash_image "dtbo" \
        "dtbo.img" "_a" "false"

    flash_image "boot" \
        "boot.img" "_a" "true"

    flash_image "odm" \
        "odm.img" "_a" "true"

    flash_image "vendor_boot" \
        "vendor_boot.img" "_a" "false"

    flash_image "vendor_dlkm" \
        "vendor_dlkm.img" "_a" "false"

    flash_image "vendor" \
        "vendor.img" "_a" "true"

    flash_image "system" \
        "system.img" "_a" "true"

    # --------------------------------------
    # Flash slot B
    # --------------------------------------

    echo "=========================================="
    echo " Flashing slot B"
    echo "=========================================="
    echo ""

    flash_image "dtbo" \
        "dtbo.img" "_b" "false"

    flash_image "boot" \
        "boot.img" "_b" "true"

    flash_image "odm" \
        "odm.img" "_b" "true"

    flash_image "vendor_boot" \
        "vendor_boot.img" "_b" "false"

    flash_image "vendor_dlkm" \
        "vendor_dlkm.img" "_b" "false"

    flash_image "vendor" \
        "vendor.img" "_b" "true"

    flash_image "system" \
        "system.img" "_b" "true"

    echo ""
    echo "=========================================="
    echo " Both slots have been installed."
    echo "=========================================="
    echo ""

    echo "Keeping previously active slot: $CURRENT_SLOT"

    fastboot set_active "$CURRENT_SLOT"

# ==========================================
# UPDATE
# ==========================================

else

    echo "=========================================="
    echo " Ubuntu Touch Update"
    echo "=========================================="
    echo ""

    echo "Current slot: $CURRENT_SLOT"
    echo "Target slot:  $TARGET_SLOT"
    echo ""

    echo "The current slot's logical partitions"
    echo "will NOT be deleted."
    echo ""

    echo "Only the target slot will be modified."
    echo ""

    echo "Update sequence:"
    echo ""
    echo "  1. Flash stock boot to boot_$CURRENT_SLOT"
    echo "  2. Reboot into recovery"
    echo "  3. Enter fastbootd"
    echo "  4. Remove target-slot logical partitions"
    echo "  5. Flash Ubuntu Touch to target slot"
    echo "  6. Flash UT boot to target slot"
    echo "  7. Activate target slot"
    echo "  8. Reboot"
    echo ""

    read -p "Continue with update? (y/N): " updatechoice

    case "$updatechoice" in
        y|Y)
            ;;
        *)
            echo "Aborting."
            exit 1
            ;;
    esac

    echo ""

    # --------------------------------------
    # Step 1
    # Temporary stock boot goes to CURRENT slot
    # --------------------------------------

    echo "=========================================="
    echo " Step 1: Temporary stock boot"
    echo "=========================================="
    echo ""

    echo "Flashing stock boot to:"
    echo "  boot_$CURRENT_SLOT"
    echo ""

    fastboot flash "boot_$CURRENT_SLOT" \
        "$IMAGE_DIR/boot_stock.img"

    echo ""

    # --------------------------------------
    # Step 2
    # Do NOT switch active slot yet.
    # --------------------------------------

    echo "=========================================="
    echo " Step 2: Rebooting into recovery"
    echo "=========================================="
    echo ""

    fastboot reboot recovery

    wait_for_fastboot

    echo ""

    # --------------------------------------
    # Step 3
    # Ensure fastbootd
    # --------------------------------------

    echo "=========================================="
    echo " Step 3: Entering fastbootd"
    echo "=========================================="
    echo ""

    ensure_fastbootd

    echo ""

    # --------------------------------------
    # Step 4
    # Delete ONLY target-slot logical
    # partitions.
    # --------------------------------------

    echo "=========================================="
    echo " Step 4: Preparing target slot"
    echo "=========================================="
    echo ""

    echo "Current slot:"
    echo "  $CURRENT_SLOT"
    echo ""

    echo "Target slot:"
    echo "  $TARGET_SLOT"
    echo ""

    echo "The following target-slot logical"
    echo "partitions may be removed:"
    echo ""
    echo "  system_$TARGET_SLOT"
    echo "  vendor_$TARGET_SLOT"
    echo "  odm_$TARGET_SLOT"
    echo ""

    fastboot delete-logical-partition \
        "system_$TARGET_SLOT" || true

    fastboot delete-logical-partition \
        "vendor_$TARGET_SLOT" || true

    fastboot delete-logical-partition \
        "odm_$TARGET_SLOT" || true

    echo ""

    # --------------------------------------
    # Step 5
    # Flash target slot
    # --------------------------------------

    echo "=========================================="
    echo " Step 5: Flashing Ubuntu Touch"
    echo "=========================================="
    echo ""

    flash_image "dtbo" \
        "dtbo.img" "$TARGET_SUFFIX" "false"

    flash_image "odm" \
        "odm.img" "$TARGET_SUFFIX" "true"

    flash_image "vendor_boot" \
        "vendor_boot.img" "$TARGET_SUFFIX" "false"

    flash_image "vendor_dlkm" \
        "vendor_dlkm.img" "$TARGET_SUFFIX" "false"

    flash_image "vendor" \
        "vendor.img" "$TARGET_SUFFIX" "true"

    flash_image "system" \
        "system.img" "$TARGET_SUFFIX" "true"

    # --------------------------------------
    # Step 6
    # Replace stock boot with UT boot
    # --------------------------------------

    echo "=========================================="
    echo " Step 6: Installing UT boot"
    echo "=========================================="
    echo ""

    flash_partition \
        "boot_$TARGET_SLOT" \
        "$IMAGE_DIR/boot.img"

    echo ""

    # --------------------------------------
    # Step 7
    # Activate target
    # --------------------------------------

    echo "=========================================="
    echo " Step 7: Activating target slot"
    echo "=========================================="
    echo ""

    echo "Setting active slot to: $TARGET_SLOT"

    fastboot set_active "$TARGET_SLOT"

    echo ""

    echo "=========================================="
    echo " Update completed successfully"
    echo "=========================================="
    echo ""

    echo "Old slot:"
    echo "  $CURRENT_SLOT"
    echo ""

    echo "Updated slot:"
    echo "  $TARGET_SLOT"
    echo ""

fi

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
