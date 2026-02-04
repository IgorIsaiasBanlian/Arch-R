#!/bin/bash

#==============================================================================
# Arch R - Root Filesystem Build Script
#==============================================================================
# Creates an Arch Linux ARM root filesystem for R36S
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

LOG_FILE="$ARCHR_OUTPUT/build-rootfs.log"
ROOTFS_DIR="$ARCHR_ROOTFS/staging"
ROOTFS_ARCHIVE="$ARCHR_OUTPUT/archr-rootfs.tar.gz"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Arch R Root Filesystem Build ==="

#------------------------------------------------------------------------------
# Check if running as root (required for chroot)
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    log "This script needs to run as root for chroot operations."
    log "Please run: sudo $0"
    exit 1
fi

#------------------------------------------------------------------------------
# Step 1: Download Arch Linux ARM base
#------------------------------------------------------------------------------
log ""
log "Step 1: Getting Arch Linux ARM base..."

ALARM_ROOTFS="$ARCHR_ROOTFS/ArchLinuxARM-aarch64-latest.tar.gz"
ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"

if [ -f "$ALARM_ROOTFS" ]; then
    log "  Base archive exists: $ALARM_ROOTFS"
else
    log "  Downloading Arch Linux ARM..."
    wget -O "$ALARM_ROOTFS" "$ALARM_URL" 2>&1 | tee -a "$LOG_FILE"
fi

#------------------------------------------------------------------------------
# Step 2: Extract rootfs
#------------------------------------------------------------------------------
log ""
log "Step 2: Extracting rootfs..."

# Clean staging directory
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

bsdtar -xpf "$ALARM_ROOTFS" -C "$ROOTFS_DIR" 2>&1 | tee -a "$LOG_FILE"
log "  Extracted to: $ROOTFS_DIR"

#------------------------------------------------------------------------------
# Step 3: Setup for chroot
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up for chroot..."

# Copy QEMU static binary for ARM64 emulation
cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"

# Mount required filesystems
mount -t proc /proc "$ROOTFS_DIR/proc"
mount -t sysfs /sys "$ROOTFS_DIR/sys"
mount -o bind /dev "$ROOTFS_DIR/dev"
mount -o bind /dev/pts "$ROOTFS_DIR/dev/pts"

# Copy DNS resolution
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

log "  Chroot environment ready"

#------------------------------------------------------------------------------
# Step 4: Configure system in chroot
#------------------------------------------------------------------------------
log ""
log "Step 4: Configuring system in chroot..."

cat > "$ROOTFS_DIR/tmp/setup.sh" << 'CHROOT_SCRIPT'
#!/bin/bash

set -e

echo "=== Inside chroot ==="

# Initialize pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Update system
pacman -Syu --noconfirm

# Install base packages
pacman -S --noconfirm --needed \
    base \
    linux-firmware \
    networkmanager \
    wpa_supplicant \
    sudo \
    vim \
    htop \
    mesa \
    sdl2 \
    alsa-utils \
    git \

# Install gaming packages
pacman -S --noconfirm --needed \
    retroarch \
    retroarch-assets-xmb \
    retroarch-assets-ozone \

# Install libretro cores (available in AUR or prebuilt)
# Note: Not all cores are in official repos
pacman -S --noconfirm --needed \
    libretro-mgba \
    libretro-snes9x \
    libretro-nestopia \
    libretro-genesis-plus-gx \
    || echo "Some cores may need to be built separately"

# Create archr user
useradd -m -G wheel -s /bin/bash archr 2>/dev/null || true
echo "archr:archr" | chpasswd

# Allow wheel group sudo
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Set hostname
echo "archr" > /etc/hostname

# Enable services
systemctl enable NetworkManager

# Set timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Generate locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Cleanup
pacman -Scc --noconfirm

echo "=== Chroot setup complete ==="
CHROOT_SCRIPT

chmod +x "$ROOTFS_DIR/tmp/setup.sh"
chroot "$ROOTFS_DIR" /tmp/setup.sh 2>&1 | tee -a "$LOG_FILE"

#------------------------------------------------------------------------------
# Step 5: Apply overlay
#------------------------------------------------------------------------------
log ""
log "Step 5: Applying overlay..."

if [ -d "$ARCHR_ROOTFS/overlay" ]; then
    cp -a "$ARCHR_ROOTFS/overlay/"* "$ROOTFS_DIR/" 2>/dev/null || true
    log "  Overlay applied"
fi

#------------------------------------------------------------------------------
# Step 6: Install kernel modules
#------------------------------------------------------------------------------
log ""
log "Step 6: Installing kernel modules..."

if [ -d "$ARCHR_OUTPUT/modules/lib/modules" ]; then
    cp -a "$ARCHR_OUTPUT/modules/lib/modules/"* "$ROOTFS_DIR/lib/modules/" 2>/dev/null || true
    log "  Modules installed"
else
    log "  WARNING: No kernel modules found. Run build-kernel.sh first."
fi

#------------------------------------------------------------------------------
# Step 7: Cleanup and unmount
#------------------------------------------------------------------------------
log ""
log "Step 7: Cleanup..."

# Remove QEMU binary
rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
rm -f "$ROOTFS_DIR/tmp/setup.sh"

# Unmount in reverse order
umount "$ROOTFS_DIR/dev/pts"
umount "$ROOTFS_DIR/dev"
umount "$ROOTFS_DIR/sys"
umount "$ROOTFS_DIR/proc"

#------------------------------------------------------------------------------
# Step 8: Create archive
#------------------------------------------------------------------------------
log ""
log "Step 8: Creating rootfs archive..."

cd "$ROOTFS_DIR"
tar -czf "$ROOTFS_ARCHIVE" .

log "  Created: $ROOTFS_ARCHIVE"
log "  Size: $(du -h "$ROOTFS_ARCHIVE" | cut -f1)"

#------------------------------------------------------------------------------
# Complete
#------------------------------------------------------------------------------
log ""
log "=== Root Filesystem Build Complete ==="
