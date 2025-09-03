#!/bin/bash
set -xe

BUILD_DIR=workdir
OUT=out

while [ $# -gt 0 ]
do
    case "$1" in
    (-b) BUILD_DIR="$2"; shift;;
    (-o) OUT="$2"; shift;;
    (-*) echo "$0: Error: unknown option $1" 1>&2; exit 1;;
    (*) OUT="$2"; break;;
    esac
    shift
done

BUILD_DIR="$(realpath "$BUILD_DIR")"
TMPDOWN="$BUILD_DIR/downloads"
OUT="$(realpath "$OUT")"
TMP="$BUILD_DIR/tmp"

source ./deviceinfo

deviceinfo_kernel_image_name="Image.lz4" ./build/make-bootimage.sh "$TMPDOWN" \
   "$TMPDOWN/KERNEL_OBJ" "$TMPDOWN/halium-boot-ramdisk.img" "$TMP/partitions/boot-lz4.img" "$TMP/system"

tar -cJf "$OUT/device_${deviceinfo_codename}.tar.xz" -C "$TMP" --owner=root --group=root partitions/ system/
# Remove compatibility hard-links to avoid confusion
rm -f "$OUT/*_usrmerge.tar.*"
