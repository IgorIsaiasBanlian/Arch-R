#!/bin/bash

#==============================================================================
# Arch R - Kernel Build Script
#==============================================================================
# Builds the Linux kernel with R36S Device Tree
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

LOG_FILE="$ARCHR_OUTPUT/build-kernel.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Arch R Kernel Build ==="

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

# Kernel source - You can use:
# 1. Rockchip BSP kernel (4.4.x) - More hardware support
# 2. Mainline kernel (5.x/6.x) - Newer features but may need more patches

KERNEL_VERSION="4.4.189"
KERNEL_SRC_DIR="$ARCHR_KERNEL/src/linux-$KERNEL_VERSION"

# If using dArkOS kernel source
DARKOS_KERNEL_URL=""  # Set this to your kernel source repo

#------------------------------------------------------------------------------
# Step 1: Check/Download Kernel Source
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking kernel source..."

if [ -d "$KERNEL_SRC_DIR" ]; then
    log "  Kernel source exists at: $KERNEL_SRC_DIR"
else
    log "  Kernel source not found!"
    log ""
    log "  You need to provide the kernel source. Options:"
    log "  1. Copy the dArkOS kernel source to: $KERNEL_SRC_DIR"
    log "  2. Clone from a git repository"
    log ""
    log "  Example:"
    log "    git clone <kernel-repo> $KERNEL_SRC_DIR"
    log ""
    exit 1
fi

#------------------------------------------------------------------------------
# Step 2: Apply R36S Device Tree
#------------------------------------------------------------------------------
log ""
log "Step 2: Checking Device Tree..."

DTS_FILE="$ARCHR_KERNEL/dts/rk3326-r36s.dts"
if [ ! -f "$DTS_FILE" ]; then
    log "  R36S DTS not found. Creating from template..."
    
    # Check if we have the original DTB to decompile
    if [ -f "$SCRIPT_DIR/../gameconsole-r36s.dtb" ]; then
        log "  Found gameconsole-r36s.dtb, decompiling..."
        dtc -I dtb -O dts "$SCRIPT_DIR/../gameconsole-r36s.dtb" -o "$DTS_FILE" 2>/dev/null
        log "  Created: $DTS_FILE"
    else
        log "  ERROR: No DTB or DTS found!"
        log "  Please place gameconsole-r36s.dtb in the parent directory"
        exit 1
    fi
fi

#------------------------------------------------------------------------------
# Step 3: Apply kernel config
#------------------------------------------------------------------------------
log ""
log "Step 3: Configuring kernel..."

CONFIG_FILE="$ARCHR_KERNEL/configs/r36s_defconfig"
if [ ! -f "$CONFIG_FILE" ]; then
    log "  No custom config found, using defconfig from kernel..."
    
    cd "$KERNEL_SRC_DIR"
    
    # Try to use existing RK3326 config
    if [ -f "arch/arm64/configs/rk3326_linux_defconfig" ]; then
        make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE rk3326_linux_defconfig
    elif [ -f "arch/arm64/configs/rockchip_linux_defconfig" ]; then
        make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE rockchip_linux_defconfig
    else
        log "  WARNING: No suitable defconfig found!"
        make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE defconfig
    fi
else
    log "  Using custom config: $CONFIG_FILE"
    cp "$CONFIG_FILE" "$KERNEL_SRC_DIR/.config"
fi

#------------------------------------------------------------------------------
# Step 4: Build kernel
#------------------------------------------------------------------------------
log ""
log "Step 4: Building kernel... (this may take a while)"

cd "$KERNEL_SRC_DIR"

# Disable warnings as errors if needed
sed -i 's/CONFIG_ERROR_ON_WARNING=y/CONFIG_ERROR_ON_WARNING=n/' .config 2>/dev/null || true

# Build kernel image
log "  Building Image..."
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE Image $MAKEFLAGS 2>&1 | tee -a "$LOG_FILE"

# Build DTBs
log "  Building Device Trees..."
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE dtbs $MAKEFLAGS 2>&1 | tee -a "$LOG_FILE"

# Build modules
log "  Building modules..."
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE modules $MAKEFLAGS 2>&1 | tee -a "$LOG_FILE"

#------------------------------------------------------------------------------
# Step 5: Install to output directory
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing kernel artifacts..."

mkdir -p "$ARCHR_OUTPUT/boot"
mkdir -p "$ARCHR_OUTPUT/modules"

# Copy kernel image
cp arch/arm64/boot/Image "$ARCHR_OUTPUT/boot/"
log "  Copied: Image"

# Copy DTB
if [ -f "arch/arm64/boot/dts/rockchip/rk3326-r36s.dtb" ]; then
    cp "arch/arm64/boot/dts/rockchip/rk3326-r36s.dtb" "$ARCHR_OUTPUT/boot/"
    log "  Copied: rk3326-r36s.dtb"
fi

# Install modules
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE \
    INSTALL_MOD_PATH="$ARCHR_OUTPUT/modules" \
    modules_install 2>&1 | tee -a "$LOG_FILE"

log "  Modules installed to: $ARCHR_OUTPUT/modules"

#------------------------------------------------------------------------------
# Complete
#------------------------------------------------------------------------------
log ""
log "=== Kernel Build Complete ==="
log ""
log "Artifacts:"
ls -la "$ARCHR_OUTPUT/boot/"
