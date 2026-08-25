# UBports for Redmi Note 13 Pro 5G / Poco X6 5G (garnet)

Halium-based Ubuntu Touch port for Xiaomi Redmi Note 13 Pro 5G / Poco X6 5G (`garnet`).

## Device Status

| Feature | Status | Notes |
| :--- | :--- | :--- |
| **Display** | Working | |
| **Touchscreen** | Working | |
| **USB OTG** | Working | |
| **Wi-Fi** | Working | |
| **Haptics** | Broken | |
| **Bluetooth** | Working | |
| **Battery & Charging** | Working | Fast charging supported |
| **Telephony** | Working | Calls, SMS, Data |
| **Waydroid** | Working | |
| **Camera** | Working | |
| **GPS** | Working | |
| **Audio** | Partial? | |
| **Fingerprint** | Broken | |
| **NFC** | Broken | |

## Known Bugs

* **Dual SIM:** Only SIM slot 1 is functional (single SIM working).
* **Recovery Mode:** Recovery mode does not work. Attempting to boot into recovery will simply boot into Ubuntu Touch anyway.
* **ADB/SSH over usb:** Doesn't work yet.
* **Flashlight:** Flashlight from quick settings doesn't work. Download the UTorch app instead.
* **Audio:** Mic and Audio may not work in calls.



## Building

```bash
./build.sh
./build/prepare-fake-ota.sh out/device_garnet_usrmerge.tar.xz ota
sudo ./build/system-image-from-ota.sh ota/ubuntu_command images
./make-installer-images.sh
