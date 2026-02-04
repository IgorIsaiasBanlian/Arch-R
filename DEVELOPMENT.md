# Arch R - Project Documentation

## Project Overview

**Arch R** is a custom Arch Linux ARM-based gaming distribution for the R36S handheld console.

## Hardware Support

- **SoC**: Rockchip RK3326
- **Display**: 640x480 (rotated portrait)
- **USB OTG**: Host mode with VBUS power control
- **Wi-Fi**: AIC8800 USB adapter (with modeswitch support from a69c:5721 to a69c:8801)
- **Multiple R36S hardware revisions**: Multiple DTB support planned

## Build Requirements

- Ubuntu 22.04+ or Arch Linux
- Cross-compilation toolchain (aarch64-linux-gnu-gcc)
- Device Tree Compiler (dtc)
- QEMU for ARM64 userspace emulation
- ~10GB disk space

## Build Process

1. **Setup toolchain**: `sudo ./setup-toolchain.sh`
2. **Source environment**: `source env.sh`
3. **Build kernel**: `./build-kernel.sh`
4. **Build rootfs**: `sudo ./build-rootfs.sh`
5. **Build image**: `sudo ./build-image.sh`

## Key Technical Notes

### USB OTG Configuration

The R36S (when using RG351MP-based firmware) had USB OTG issues due to:
- `otg-port` status set to "disabled" in Device Tree
- `dr_mode` set to "otg" instead of "host"
- Missing `vbus-supply` reference to `otg_switch` regulator (phandle 0xec)

**Solution**: Modify Device Tree to:
```
usb@ff300000 {
    dr_mode = "host";  // Force host mode
};

otg-port {
    status = "okay";    // Enable OTG port
    vbus-supply = <&otg_switch>;  // Reference power regulator
};
```

### Wi-Fi Modeswitch

The AIC8800 USB adapter appears first as a CD-ROM device (VID:PID a69c:5721).
A udev rule triggers `/usr/bin/eject` to switch it to Wi-Fi mode (a69c:8801).

See: `config/udev/99-archr-r36s.rules`

### Multiple R36S Revisions

The R36S has multiple hardware revisions requiring different Device Trees.
The build system should be updated to:
1. Include all DTB variants in `/kernel/dts/`
2. Auto-detect hardware revision at boot
3. Load appropriate DTB

## Directory Structure

```
arch-r/
├── bootloader/          # U-Boot configuration
│   └── configs/
├── kernel/              # Kernel and Device Trees
│   ├── configs/         # Kernel defconfig
│   ├── dts/             # Device Tree sources/binaries
│   └── patches/         # Kernel patches
├── rootfs/              # Root filesystem
│   └── overlay/         # Files to overlay on rootfs
├── config/              # System configuration
│   ├── retroarch.cfg    # RetroArch config for R36S
│   └── udev/            # udev rules
├── scripts/             # Runtime scripts
└── output/              # Build artifacts
```

## References

- Kernel: dArkOS kernel source (4.4.189)
- Base system: Arch Linux ARM aarch64
- Frontend: RetroArch + EmulationStation
