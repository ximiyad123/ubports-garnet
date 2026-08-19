# shellcheck shell=sh

# Copyright (C) 2021-2022 UBports Foundation.
# SPDX-License-Identifier: GPL-3.0-or-later

ab_slot_detect_done=""
ab_slot_suffix=""

# Cache for partition name to device mapping from sysfs
partname_cache=""
partname_cache_built=""

# Build partition name cache from /sys/class/block/*/uevent
# This is used as a fallback when /dev/disk/by-* is not yet available (before udev coldboot)
build_partname_cache() {
    if [ -n "$partname_cache_built" ]; then
        return
    fi

    partname_cache=""
    for uevent in /sys/class/block/*/uevent; do
        [ -e "$uevent" ] || continue

        devname=""
        partname=""

        while IFS='=' read -r key value; do
            case "$key" in
                DEVNAME)
                    devname="$value"
                    ;;
                PARTNAME)
                    partname="$value"
                    ;;
            esac
        done < "$uevent"

        if [ -n "$devname" ] && [ -n "$partname" ]; then
            # Store as "partname:devname" pairs, newline separated
            if [ -z "$partname_cache" ]; then
                partname_cache="${partname}:${devname}"
            else
                partname_cache="${partname_cache}
${partname}:${devname}"
            fi
        fi
    done

    partname_cache_built=1
}

# Lookup partition by name in the cache
# $1=partition name
# Returns device path if found
lookup_partname_cache() {
    search_name="$1"

    echo "$partname_cache" | while IFS=: read -r partname devname; do
        if [ "$partname" = "$search_name" ]; then
            echo "/dev/${devname}"
            return 0
        fi
    done
}

find_partition_path() {
    # Note that we run early before udev coldboot, so if we boot without initrd,
    # /dev/disk/by-* might not be available. We use /sys/class/block/*/uevent
    # as a fallback to find partitions by PARTNAME.

    partname="$1"
    device_path=""

    if [ -z "$ab_slot_detect_done" ]; then
        if [ -e /proc/bootconfig ]; then
            ab_slot_suffix=$(grep -o 'androidboot\.slot_suffix = ".."' /proc/bootconfig | cut -d '"' -f2)
        fi
        if [ -z "$ab_slot_suffix" ]; then
            ab_slot_suffix=$(grep -o 'androidboot\.slot_suffix=..' /proc/cmdline |  cut -d "=" -f2)
        fi
        if [ -n "$ab_slot_suffix" ]; then
            echo "Detected slot suffix $ab_slot_suffix" >&2
        fi
        ab_slot_detect_done=1
    fi

    # Try /dev/disk/by-partlabel/ and /dev/mapper/ first
    for detection in \
            /dev/disk/by-partlabel/ \
            /dev/mapper/ \
    ; do
        device_path="${detection}${partname}"
        if [ -e "$device_path" ]; then
            echo "$device_path"
            return 0
        fi

        # Try with A/B slot suffix if detected
        if [ -n "$ab_slot_suffix" ]; then
            device_path="${detection}${partname}${ab_slot_suffix}"
            if [ -e "$device_path" ]; then
                echo "$device_path"
                return 0
            fi
        fi
    done

    # Fallback: scan /sys/class/block/*/uevent in case /dev/disk/by-partlabel
    # paths might not be available
    build_partname_cache

    device_path=$(lookup_partname_cache "$partname")
    if [ -n "$device_path" ] && [ -e "$device_path" ]; then
        echo "$device_path"
        return 0
    fi

    # Try with A/B slot suffix in the cache
    if [ -n "$ab_slot_suffix" ]; then
        device_path=$(lookup_partname_cache "${partname}${ab_slot_suffix}")
        if [ -n "$device_path" ] && [ -e "$device_path" ]; then
            echo "$device_path"
            return 0
        fi
    fi

    # Not found
    return 1
}
