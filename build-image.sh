#!/bin/bash

#==============================================================================
# Arch R - SD Card Image Build Script
#==============================================================================
# Creates a bootable SD card image for R36S
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment
if [ -f "$SCRIPT_DIR/env.sh" ]; then
    source "$SCRIPT_DIR/env.sh"
else
    echo "ERROR: env.sh not found!"
    exit 1
fi

LOG_FILE="$ARCHR_OUTPUT/build-image.log"
IMAGE_FILE="$ARCHR_OUTPUT/archr-r36s.img"
IMAGE_SIZE="4G"  # Minimum image size

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Arch R Image Build ==="

#------------------------------------------------------------------------------
# Check root
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    log "This script needs root for loop device operations."
    log "Please run: sudo $0"
    exit 1
fi

#------------------------------------------------------------------------------
# Check prerequisites
#------------------------------------------------------------------------------
log ""
log "Checking prerequisites..."

BOOT_FILES="$ARCHR_OUTPUT/boot"
ROOTFS_ARCHIVE="$ARCHR_OUTPUT/archr-rootfs.tar.gz"

if [ ! -d "$BOOT_FILES" ] || [ ! -f "$BOOT_FILES/Image" ]; then
    log "ERROR: Kernel not built. Run build-kernel.sh first."
    exit 1
fi

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    log "ERROR: Rootfs not built. Run build-rootfs.sh first."
    exit 1
fi

log "  Prerequisites OK"

#------------------------------------------------------------------------------
# Step 1: Create image file
#------------------------------------------------------------------------------
log ""
log "Step 1: Creating image file..."

rm -f "$IMAGE_FILE"
truncate -s "$IMAGE_SIZE" "$IMAGE_FILE"
log "  Created: $IMAGE_FILE ($IMAGE_SIZE)"

#------------------------------------------------------------------------------
# Step 2: Partition image
#------------------------------------------------------------------------------
log ""
log "Step 2: Partitioning image..."

# Partition layout:
# 0MB-1MB:    Reserved for bootloader (idbloader, u-boot)
# 1MB-129MB:  Boot partition (FAT32)
# 129MB-end:  Root partition (ext4)

parted -s "$IMAGE_FILE" mklabel msdos
parted -s "$IMAGE_FILE" mkpart primary fat32 1MiB 129MiB
parted -s "$IMAGE_FILE" mkpart primary ext4 129MiB 100%
parted -s "$IMAGE_FILE" set 1 boot on

log "  Partitions created"

#------------------------------------------------------------------------------
# Step 3: Setup loop device
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up loop device..."

LOOP_DEV=$(losetup --find --show --partscan "$IMAGE_FILE")
log "  Loop device: $LOOP_DEV"

# Wait for partitions to appear
sleep 2

BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

#------------------------------------------------------------------------------
# Step 4: Format partitions
#------------------------------------------------------------------------------
log ""
log "Step 4: Formatting partitions..."

mkfs.vfat -F 32 -n BOOT "$BOOT_PART"
log "  Formatted: $BOOT_PART (FAT32)"

mkfs.ext4 -L ROOT "$ROOT_PART"
log "  Formatted: $ROOT_PART (ext4)"

#------------------------------------------------------------------------------
# Step 5: Mount and populate
#------------------------------------------------------------------------------
log ""
log "Step 5: Mounting partitions..."

MOUNT_DIR="$ARCHR_OUTPUT/mnt"
BOOT_MOUNT="$MOUNT_DIR/boot"
ROOT_MOUNT="$MOUNT_DIR/root"

mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
mount "$BOOT_PART" "$BOOT_MOUNT"
mount "$ROOT_PART" "$ROOT_MOUNT"

log "  Mounted partitions"

#------------------------------------------------------------------------------
# Step 6: Copy boot files
#------------------------------------------------------------------------------
log ""
log "Step 6: Copying boot files..."

# Copy kernel
cp "$BOOT_FILES/Image" "$BOOT_MOUNT/"
log "  Copied: Image"

# Copy DTB
if [ -f "$BOOT_FILES/rk3326-r36s.dtb" ]; then
    cp "$BOOT_FILES/rk3326-r36s.dtb" "$BOOT_MOUNT/"
    log "  Copied: rk3326-r36s.dtb"
fi

# Create boot.ini for R36S
cat > "$BOOT_MOUNT/boot.ini" << 'EOF'
# Arch R Boot Configuration for R36S

setenv bootargs "root=/dev/mmcblk0p2 rootwait rw console=ttyFIQ0 quiet splash loglevel=0"

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 ${loadaddr} Image
load mmc 1:1 ${dtb_loadaddr} rk3326-r36s.dtb

booti ${loadaddr} - ${dtb_loadaddr}
EOF

log "  Created: boot.ini"

#------------------------------------------------------------------------------
# Step 7: Extract rootfs
#------------------------------------------------------------------------------
log ""
log "Step 7: Extracting rootfs..."

tar -xzf "$ROOTFS_ARCHIVE" -C "$ROOT_MOUNT/"
log "  Rootfs extracted"

# Create fstab
cat > "$ROOT_MOUNT/etc/fstab" << 'EOF'
# Arch R fstab
/dev/mmcblk0p1  /boot   vfat    defaults        0 2
/dev/mmcblk0p2  /       ext4    defaults,noatime 0 1
EOF

log "  Created: /etc/fstab"

#------------------------------------------------------------------------------
# Step 8: Install bootloader (if available)
#------------------------------------------------------------------------------
log ""
log "Step 8: Installing bootloader..."

UBOOT_DIR="$ARCHR_BOOTLOADER/output"
if [ -f "$UBOOT_DIR/idbloader.img" ] && [ -f "$UBOOT_DIR/u-boot.itb" ]; then
    dd if="$UBOOT_DIR/idbloader.img" of="$LOOP_DEV" seek=64 conv=notrunc
    dd if="$UBOOT_DIR/u-boot.itb" of="$LOOP_DEV" seek=16384 conv=notrunc
    log "  Bootloader installed"
else
    log "  WARNING: U-Boot not found. You may need to install it manually."
    log "  For now, the image will use the existing bootloader on SD card."
fi

#------------------------------------------------------------------------------
# Step 9: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 9: Cleanup..."

sync
umount "$BOOT_MOUNT"
umount "$ROOT_MOUNT"
losetup -d "$LOOP_DEV"

rmdir "$BOOT_MOUNT" "$ROOT_MOUNT" "$MOUNT_DIR"

log "  Cleanup complete"

#------------------------------------------------------------------------------
# Step 10: Compress image
#------------------------------------------------------------------------------
log ""
log "Step 10: Compressing image..."

xz -z -k -9 -T 0 "$IMAGE_FILE" 2>&1 | tee -a "$LOG_FILE"
log "  Created: ${IMAGE_FILE}.xz"

#------------------------------------------------------------------------------
# Complete
#------------------------------------------------------------------------------
log ""
log "=== Image Build Complete ==="
log ""
log "Output files:"
ls -lh "$IMAGE_FILE"*
log ""
log "To flash to SD card:"
log "  xzcat ${IMAGE_FILE}.xz | sudo dd of=/dev/sdX bs=4M status=progress"
