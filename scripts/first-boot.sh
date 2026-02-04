#!/bin/bash

#==============================================================================
# Arch R - First Boot Setup Script
#==============================================================================
# Runs on first boot to configure the system
#==============================================================================

FIRST_BOOT_FLAG="/var/lib/archr/.first-boot-done"

# Check if already ran
if [ -f "$FIRST_BOOT_FLAG" ]; then
    exit 0
fi

echo "=== Arch R First Boot Setup ==="

#------------------------------------------------------------------------------
# Resize partition to fill SD card
#------------------------------------------------------------------------------
echo "Resizing root partition..."

ROOT_DEV="/dev/mmcblk0p2"
ROOT_DISK="/dev/mmcblk0"

# Get current end and max available
PART_INFO=$(parted -m "$ROOT_DISK" unit s print 2>/dev/null | grep "^2:")
CURRENT_END=$(echo "$PART_INFO" | cut -d: -f3 | tr -d 's')

DISK_SIZE=$(parted -m "$ROOT_DISK" unit s print 2>/dev/null | grep "^$ROOT_DISK" | cut -d: -f2 | tr -d 's')
MAX_END=$((DISK_SIZE - 34))  # Leave space for GPT backup

if [ "$CURRENT_END" -lt "$MAX_END" ]; then
    echo "  Expanding partition..."
    parted -s "$ROOT_DISK" resizepart 2 100%
    resize2fs "$ROOT_DEV"
    echo "  Partition expanded!"
else
    echo "  Partition already at maximum size"
fi

#------------------------------------------------------------------------------
# Generate SSH host keys
#------------------------------------------------------------------------------
echo "Generating SSH host keys..."
ssh-keygen -A 2>/dev/null || true

#------------------------------------------------------------------------------
# Set random machine-id
#------------------------------------------------------------------------------
echo "Generating machine ID..."
rm -f /etc/machine-id
systemd-machine-id-setup

#------------------------------------------------------------------------------
# Enable services
#------------------------------------------------------------------------------
echo "Enabling services..."
systemctl enable NetworkManager 2>/dev/null || true
systemctl enable bluetooth 2>/dev/null || true

#------------------------------------------------------------------------------
# Configure RetroArch
#------------------------------------------------------------------------------
echo "Configuring RetroArch..."

RA_CONFIG="/home/archr/.config/retroarch/retroarch.cfg"
mkdir -p "$(dirname "$RA_CONFIG")"

if [ ! -f "$RA_CONFIG" ]; then
    cp /etc/archr/retroarch.cfg "$RA_CONFIG" 2>/dev/null || true
fi

chown -R archr:archr /home/archr/.config 2>/dev/null || true

#------------------------------------------------------------------------------
# Create ROM directories
#------------------------------------------------------------------------------
echo "Creating ROM directories..."

ROM_BASE="/home/archr/roms"
SYSTEMS=(
    "gb" "gbc" "gba" "nes" "snes" "megadrive" "psx"
    "n64" "psp" "dreamcast" "arcade" "mame"
)

for sys in "${SYSTEMS[@]}"; do
    mkdir -p "$ROM_BASE/$sys"
done

chown -R archr:archr "$ROM_BASE"

#------------------------------------------------------------------------------
# Mark first boot complete
#------------------------------------------------------------------------------
mkdir -p "$(dirname "$FIRST_BOOT_FLAG")"
touch "$FIRST_BOOT_FLAG"

echo "=== First Boot Setup Complete ==="
echo ""
echo "System will continue booting..."
