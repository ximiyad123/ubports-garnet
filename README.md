# ubports-garnet

Ubuntu Touch / Halium port for the **Redmi Note 13 Pro 5G / POCO X6** (codename `garnet`, Qualcomm SM7435).

> **Status: bring-up / not booting to UI.** Kernel boots, hardware drivers largely work, no rootfs flashed yet. See [Status](#status) below.

## Device

| | |
|---|---|
| Manufacturer | Xiaomi |
| Model | Redmi Note 13 Pro 5G / POCO X6 |
| Codename | garnet |
| SoC | Qualcomm SM7435 (Snapdragon 7s Gen 2) |
| Arch | aarch64 |
| Kernel | 5.10.245-gki-g4e825ba35213 |
| Halium | 12 |
| Ubuntu Touch target | 24.04-2.x |

## Status

### Working
- Kernel boots without panicking (**CFI temporarily disabled** — see [Known Issues](#known-issues))
- USB gadget networking + `telnetd` debug shell (port 23, `192.168.2.15`)
- Touchscreen (Focaltech `focaltech_3683g`) — confirmed producing correct coordinates
- Module loading (312 `.ko` modules, flat `modules.load`/`modules.blocklist` scheme)
- UFS/storage, dynamic partitions (`system_b`, `vendor_b`, `vendor_dlkm_b`, etc.) mount cleanly
- Prebuilt DTB, split GKI boot/vendor_boot/init_boot partition layout

### Not yet done
- No Ubuntu Touch rootfs has been flashed/tested yet — everything above was verified from the Halium debug initrd only
- `switch_root` into a real UT rootfs, hybris/lxc Android container start, and Lomiri/Unity8 launch are all unverified
- Firmware blob loading (WiFi/BT/modem/ADSP via bind-mounted `vendor`/`vendor_dlkm`) is expected to work automatically once the container starts, but has not been confirmed on this device

## Known Issues

- **CFI is disabled.** A duplicate driver-registration race between `focaltech_3683g.ko` and `focaltech_fts.ko` was causing a kernel panic during `i2c_msm_geni` probe. Not yet resolved properly — CFI should be re-enabled once it is.
- **`nt36xxx_i2c`/`nt36xxx_spi` load alongside the working Focaltech driver** even though only one touch panel is present per unit.

## Building

```bash
./build.sh
```

Pulls [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools), builds the kernel/rootfs images, then runs `make-bootimages.sh` to produce flashable boot/vendor_boot/recovery images.

## Debugging

If a build fails to reach the normal boot UI, a debug shell is available over USB:

```bash
sudo ip addr add 192.168.2.1/24 dev <your-usb-iface>
sudo ip link set <your-usb-iface> up
telnet 192.168.2.15 23
```

Note: **use plain `/dev/sdX` paths, not `/dev/block/sdX`**, when poking around block devices from this shell — no `/dev/block/` mirror is populated in this initrd. Partition names are readable via:
```sh
grep PARTNAME /sys/class/block/*/uevent
```
Dynamic (super) partitions are pre-resolved under `/dev/mapper/` (e.g. `/dev/mapper/system_b`) — check `/proc/cmdline`'s `androidboot.slot_suffix`/bootconfig for the active slot rather than assuming.

If USB networking never comes up and no crashdump is available, the kernel's minidump partition (`PARTNAME=minidump`) can be pulled from a working Android boot (if still dual-booting stock) for postmortem analysis with `strings`/manual parsing of the embedded `md_kmsg` segment.

## Credits / Sources

- Kernel: [ximiyad123/android_kernel_xiaomi_sm7435](https://github.com/ximiyad123/android_kernel_xiaomi_sm7435) (`lineage-halium-23.0`)
- Kernel modules: [LineageOS/android_kernel_xiaomi_sm7435-modules](https://github.com/LineageOS/android_kernel_xiaomi_sm7435-modules) (`lineage-23.0`)
- Build tooling: [halium-generic-adaptation-build-tools](https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools)
