#!/usr/bin/bash

set -e

BUILD_DIR=$(pwd)
INSTALL_SCRIPTS="$BUILD_DIR/installer-scripts"
WORKDIR="$BUILD_DIR/workdir"
TARGET="$WORKDIR/tmp/installer_scripts"
OUTPUT_DIR="$BUILD_DIR/out"
ZIP_NAME="ubports-garnet-installer-$(date +%Y%m%d).zip"

if [ ! -d "$INSTALL_SCRIPTS" ]; then
    echo "E: Source directory $INSTALL_SCRIPTS does not exist!"
    exit 1
fi

echo "I: Preparing working directories..."
rm -rf "$TARGET"
mkdir -p "$TARGET/images" "$OUTPUT_DIR"

echo "I: Copying script files..."
cp -r "$INSTALL_SCRIPTS"/* "$TARGET/"

echo "I: Copying image files..."
for img in "$BUILD_DIR"/images/*; do
    [ -f "$img" ] || continue
    case "$img" in
        *boot-lz4.img|*rootfs.img) continue ;;
        *) cp "$img" "$TARGET/images/" ;;
    esac
done

echo "I: Repacking image files..."
cd "$TARGET"
zip -r "$OUTPUT_DIR/$ZIP_NAME" .

echo "+: Success! Output saved to $OUTPUT_DIR/$ZIP_NAME"
