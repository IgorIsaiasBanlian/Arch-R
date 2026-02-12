#!/bin/bash

#==============================================================================
# Arch R - Root Filesystem Build Script
#==============================================================================
# Creates a minimal Arch Linux ARM rootfs optimized for R36S gaming
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

OUTPUT_DIR="$SCRIPT_DIR/output"
ROOTFS_DIR="$OUTPUT_DIR/rootfs"
CACHE_DIR="$SCRIPT_DIR/.cache"

# Arch Linux ARM rootfs
ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
ALARM_TARBALL="$CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz"

log "=== Arch R Rootfs Build ==="

#------------------------------------------------------------------------------
# Root check
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (for chroot and permissions)"
fi

#------------------------------------------------------------------------------
# Step 1: Download Arch Linux ARM
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking Arch Linux ARM tarball..."

mkdir -p "$CACHE_DIR"

if [ ! -f "$ALARM_TARBALL" ]; then
    log "  Downloading Arch Linux ARM..."
    wget -O "$ALARM_TARBALL" "$ALARM_URL"
else
    log "  ✓ Using cached tarball"
fi

#------------------------------------------------------------------------------
# Step 2: Extract Base System
#------------------------------------------------------------------------------
log ""
log "Step 2: Extracting base system..."

# Clean previous rootfs (unmount stale bind mounts first)
if [ -d "$ROOTFS_DIR" ]; then
    warn "Removing existing rootfs..."
    for mp in run sys proc dev/pts dev; do
        mountpoint -q "$ROOTFS_DIR/$mp" 2>/dev/null && umount -l "$ROOTFS_DIR/$mp" 2>/dev/null || true
    done
    rm -rf "$ROOTFS_DIR"
fi

mkdir -p "$ROOTFS_DIR"

log "  Extracting... (this may take a while)"
bsdtar -xpf "$ALARM_TARBALL" -C "$ROOTFS_DIR"

log "  ✓ Base system extracted"

#------------------------------------------------------------------------------
# Step 3: Setup for chroot
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up chroot environment..."

# Copy QEMU for ARM64 emulation
if [ -f "/usr/bin/qemu-aarch64-static" ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
    log "  ✓ QEMU static copied"
else
    warn "qemu-aarch64-static not found, chroot may not work"
    warn "Install with: sudo apt install qemu-user-static"
fi

# Bind mounts
mount --bind /dev "$ROOTFS_DIR/dev"
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
mount --bind /proc "$ROOTFS_DIR/proc"
mount --bind /sys "$ROOTFS_DIR/sys"
mount --bind /run "$ROOTFS_DIR/run"

# DNS resolution
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

log "  ✓ Chroot environment ready"

# Fix pacman for QEMU chroot environment
# - Disable CheckSpace (mount point detection fails in chroot)
sed -i 's/^CheckSpace/#CheckSpace/' "$ROOTFS_DIR/etc/pacman.conf"
log "  ✓ Pacman CheckSpace disabled (QEMU chroot compatibility)"

# Add multiple fallback mirrors (default mirror often has stale/404 packages)
cat > "$ROOTFS_DIR/etc/pacman.d/mirrorlist" << 'MIRRORS_EOF'
# Arch Linux ARM mirrors - multiple fallbacks for reliability
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://eu.mirror.archlinuxarm.org/$arch/$repo
Server = http://dk.mirror.archlinuxarm.org/$arch/$repo
Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
Server = http://hu.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
MIRRORS_EOF
log "  ✓ Multiple ALARM mirrors configured (fallback for 404s)"

#------------------------------------------------------------------------------
# Step 4: Configure System
#------------------------------------------------------------------------------
log ""
log "Step 4: Configuring system..."

# Create setup script to run inside chroot
cat > "$ROOTFS_DIR/tmp/setup.sh" << 'SETUP_EOF'
#!/bin/bash
set -e

echo "=== Inside chroot ==="

# Disable pacman Landlock sandbox (fails in QEMU chroot)
# Shell function wraps all pacman calls with --disable-sandbox
pacman() { command pacman --disable-sandbox "$@"; }
echo "  Pacman sandbox disabled (--disable-sandbox wrapper)"

# Initialize pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Full system upgrade — multiple mirrors configured for 404 fallback
pacman -Syu --noconfirm --disable-download-timeout

# Install essential packages
pacman -S --noconfirm --needed \
    base \
    linux-firmware \
    networkmanager \
    wpa_supplicant \
    dhcpcd \
    sudo \
    nano \
    htop \
    wget \
    usb_modeswitch \
    dosfstools \
    parted

# Audio
pacman -S --noconfirm --needed \
    alsa-utils \
    alsa-plugins

# Bluetooth
pacman -S --noconfirm --needed \
    bluez \
    bluez-utils

# Graphics & GPU
pacman -S --noconfirm --needed \
    mesa \
    libdrm \
    sdl2 \
    sdl2_mixer \
    sdl2_image \
    sdl2_ttf

# Gaming stack dependencies
# Note: freeimage is not in ALARM repos — installed in build-emulationstation.sh
pacman -S --noconfirm --needed \
    retroarch \
    libretro-core-info \
    freetype2 \
    libglvnd \
    curl \
    unzip \
    p7zip \
    evtest \
    brightnessctl \
    python-evdev

# LibRetro cores — install each individually (some may not exist in ALARM)
for core in libretro-snes9x libretro-gambatte libretro-mgba \
            libretro-genesis-plus-gx libretro-pcsx-rearmed libretro-flycast \
            libretro-beetle-pce-fast libretro-scummvm libretro-melonds \
            libretro-nestopia libretro-picodrive; do
    pacman -S --noconfirm --needed "$core" 2>/dev/null \
        && echo "  Installed: $core" \
        || echo "  Not available: $core (will use pre-compiled)"
done

# Download pre-compiled cores for those not in pacman repos
# Source: christianhaitian/retroarch-cores (optimized for ARM devices)
echo "Downloading additional libretro cores..."
CORES_URL="https://raw.githubusercontent.com/christianhaitian/retroarch-cores/master/aarch64"
CORES_DIR="/usr/lib/libretro"
mkdir -p "$CORES_DIR"

for core in fceumm_libretro.so mupen64plus_next_libretro.so \
            fbneo_libretro.so mame2003_plus_libretro.so \
            stella_libretro.so mednafen_wswan_libretro.so \
            ppsspp_libretro.so desmume2015_libretro.so; do
    if [ ! -f "$CORES_DIR/$core" ]; then
        wget -q -O "$CORES_DIR/$core" "$CORES_URL/$core" 2>/dev/null \
            && echo "  Downloaded: $core" \
            || echo "  Failed to download: $core (can be installed later)"
    fi
done

# Enable services
systemctl enable NetworkManager

# Disable unnecessary services for faster boot
systemctl disable systemd-timesyncd 2>/dev/null || true
systemctl disable dhcpcd 2>/dev/null || true
systemctl disable remote-fs.target 2>/dev/null || true

# Create gaming user 'archr'
if ! id archr &>/dev/null; then
    useradd -m -G wheel,audio,video,render,input -s /bin/bash archr
    echo "archr:archr" | chpasswd
fi

# Allow wheel group passwordless sudo
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd

# Set hostname
echo "archr" > /etc/hostname

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Performance tuning
cat > /etc/sysctl.d/99-archr.conf << 'SYSCTL_EOF'
# Arch R Performance Tuning
vm.swappiness=10
vm.dirty_ratio=20
vm.dirty_background_ratio=5
kernel.sched_latency_ns=1000000
kernel.sched_min_granularity_ns=500000
SYSCTL_EOF

# Enable ZRAM swap
cat > /etc/systemd/system/zram-swap.service << 'ZRAM_EOF'
[Unit]
Description=ZRAM Swap
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram && echo lzo > /sys/block/zram0/comp_algorithm && echo 268435456 > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 && echo 1 > /sys/block/zram0/reset'

[Install]
WantedBy=multi-user.target
ZRAM_EOF

systemctl enable zram-swap

# Create directories
mkdir -p /home/archr/.config/retroarch/cores
mkdir -p /home/archr/.config/retroarch/saves
mkdir -p /home/archr/.config/retroarch/states
mkdir -p /home/archr/.config/retroarch/screenshots
mkdir -p /roms
chown -R archr:archr /home/archr

# Add ROMS partition to fstab (firstboot creates the partition)
if ! grep -q '/roms' /etc/fstab; then
    echo '# ROMS partition (created by firstboot)'  >> /etc/fstab
    echo '/dev/mmcblk1p3  /roms  vfat  defaults,utf8,noatime,nofail,x-systemd.device-timeout=5s  0  0' >> /etc/fstab
fi

# Firstboot service
cat > /etc/systemd/system/firstboot.service << 'FB_EOF'
[Unit]
Description=Arch R First Boot Setup
Before=emulationstation.service
ConditionPathExists=!/var/lib/archr/.first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FB_EOF

systemctl enable firstboot

# EmulationStation launch — via autologin + .bash_profile (proven dArkOS approach)
# NOT a systemd service! ES needs a real VT session for KMSDRM DRM master access.
# Flow: getty@tty1 autologin → archr shell → .bash_profile → emulationstation.sh
# The autologin override is created above (getty@tty1.service.d/autologin.conf)

# Boot-time setup service (runs as root before ES: governors + DRM permissions)
cat > /etc/systemd/system/archr-boot-setup.service << 'SETUP_EOF'
[Unit]
Description=Arch R Boot Setup (governors + DRM permissions)
After=systemd-modules-load.service
Before=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'chmod 666 /dev/dri/* 2>/dev/null; echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null; echo performance > /sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/governor 2>/dev/null; echo dmc_ondemand > /sys/devices/platform/dmc/devfreq/dmc/governor 2>/dev/null; true'

[Install]
WantedBy=multi-user.target
SETUP_EOF

systemctl enable archr-boot-setup

# .bash_profile for archr — launches EmulationStation on tty1 only
cat > /home/archr/.bash_profile << 'PROFILE_EOF'
# Arch R: Auto-launch EmulationStation on tty1
# SSH and serial sessions (tty2+) get a normal shell
if [ "$(tty)" = "/dev/tty1" ]; then
    exec /usr/bin/emulationstation/emulationstation.sh
fi
PROFILE_EOF
chown archr:archr /home/archr/.bash_profile

# Boot splash service (very early — shows splash on fb0 before anything else)
cat > /etc/systemd/system/splash.service << 'SPLASH_EOF'
[Unit]
Description=Arch R Boot Splash
DefaultDependencies=no
After=systemd-tmpfiles-setup-dev.service
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/splash-show.sh
RemainAfterExit=yes
StandardInput=null
StandardOutput=null
StandardError=null

[Install]
WantedBy=sysinit.target
SPLASH_EOF

systemctl enable splash

# Battery LED warning service
cat > /etc/systemd/system/battery-led.service << 'BATT_EOF'
[Unit]
Description=Arch R Battery LED Warning
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/batt_life_warning.py
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
BATT_EOF

systemctl enable battery-led

# Hotkey daemon (volume/brightness — replaces dArkOS ogage)
cat > /etc/systemd/system/archr-hotkeys.service << 'HK_EOF'
[Unit]
Description=Arch R Hotkey Daemon (volume/brightness)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/archr-hotkeys.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
HK_EOF

systemctl enable archr-hotkeys

# Sudoers for perfmax/perfnorm (allow archr to run without password)
echo "archr ALL=(ALL) NOPASSWD: /usr/local/bin/perfmax, /usr/local/bin/perfnorm" > /etc/sudoers.d/archr-perf
chmod 440 /etc/sudoers.d/archr-perf

# Allow archr to use negative nice values (needed for nice -n -19 in ES launch commands)
echo "archr  -  nice  -20" >> /etc/security/limits.conf

# Distro version info
cat > /etc/archr-release << 'VER_EOF'
NAME="Arch R"
VERSION="1.0"
ID=archr
ID_LIKE=arch
BUILD_DATE="$(date +%Y-%m-%d)"
VARIANT="R36S"
VER_EOF

# Auto-login on tty1 (fallback if ES not installed)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin archr --noclear %I $TERM
AL_EOF

# Journald size limit (save memory)
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf << 'JD_EOF'
[Journal]
SystemMaxUse=16M
RuntimeMaxUse=16M
JD_EOF

# Suppress login messages (silent boot)
touch /home/archr/.hushlogin
chown archr:archr /home/archr/.hushlogin

#------------------------------------------------------------------------------
# System Optimization
#------------------------------------------------------------------------------
echo "=== System Optimization ==="

# Note: tmpfs entries for /tmp and /var/log are set in build-image.sh's fstab
# (build-image.sh creates a fresh fstab that overrides what's in the rootfs)

# Disable services that are not needed on this device
# NOTE: bluetooth, wifi, rfkill are left enabled — user decides what to use
systemctl disable lvm2-monitor 2>/dev/null || true
systemctl mask lvm2-lvmpolld.service lvm2-lvmpolld.socket 2>/dev/null || true

# Disable Mali blob from ld.so.conf — use Mesa Panfrost instead
# Mali's old libgbm.so (2020) is incompatible with modern SDL3/sdl2-compat
# Mali libs stay in /usr/lib/mali-egl/ for manual use if needed
if [ -f /etc/ld.so.conf.d/mali.conf ]; then
    mv /etc/ld.so.conf.d/mali.conf /etc/ld.so.conf.d/mali.conf.disabled
    ldconfig
fi

# Reduce kernel messages on console
echo 'kernel.printk = 3 3 3 3' >> /etc/sysctl.d/99-archr.conf

# Faster TTY login (skip issue/motd)
echo "" > /etc/issue
echo "" > /etc/motd

# ALSA default config for RK3326 (rk817 codec)
cat > /etc/asound.conf << 'ALSA_EOF'
# Arch R ALSA configuration for RK3326 (rk817 codec)
pcm.!default {
    type hw
    card 0
    device 0
}
ctl.!default {
    type hw
    card 0
}
ALSA_EOF

# Set default audio levels
amixer -c 0 sset 'Playback Path' SPK 2>/dev/null || true
amixer -c 0 sset 'Master' 80% 2>/dev/null || true

# Disable coredumps (save space)
echo 'kernel.core_pattern=|/bin/false' >> /etc/sysctl.d/99-archr.conf
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf << 'CORE_EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
CORE_EOF

# Network defaults (WiFi powersave off for lower latency)
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/archr.conf << 'NM_EOF'
[connection]
wifi.powersave=2
NM_EOF

# Clean package cache
pacman -Scc --noconfirm

echo "=== Chroot setup complete ==="
SETUP_EOF

chmod +x "$ROOTFS_DIR/tmp/setup.sh"

# Run setup inside chroot
log "  Running setup inside chroot..."
chroot "$ROOTFS_DIR" /tmp/setup.sh

log "  ✓ System configured"

#------------------------------------------------------------------------------
# Step 5: Install Arch R Scripts and Configs
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing Arch R scripts and configs..."

# Performance scripts
install -m 755 "$SCRIPT_DIR/scripts/perfmax" "$ROOTFS_DIR/usr/local/bin/perfmax"
install -m 755 "$SCRIPT_DIR/scripts/perfnorm" "$ROOTFS_DIR/usr/local/bin/perfnorm"
log "  ✓ Performance scripts installed"

# ES info bar scripts (called by ES-fcamod for status display)
install -m 755 "$SCRIPT_DIR/scripts/current_volume" "$ROOTFS_DIR/usr/local/bin/current_volume"
install -m 755 "$SCRIPT_DIR/scripts/current_brightness" "$ROOTFS_DIR/usr/local/bin/current_brightness"
log "  ✓ ES info bar scripts installed (current_volume, current_brightness)"

# Distro version for ES info bar (ES reads title= from this file)
mkdir -p "$ROOTFS_DIR/usr/share/plymouth/themes"
echo "title=Arch R v1.0 ($(date +%Y-%m-%d))" > "$ROOTFS_DIR/usr/share/plymouth/themes/text.plymouth"
log "  ✓ Distro version installed (text.plymouth)"

# Splash screen script
install -m 755 "$SCRIPT_DIR/scripts/splash-show.sh" "$ROOTFS_DIR/usr/local/bin/splash-show.sh"
log "  ✓ Splash script installed"

# First boot script
install -m 755 "$SCRIPT_DIR/scripts/first-boot.sh" "$ROOTFS_DIR/usr/local/bin/first-boot.sh"
log "  ✓ First boot script installed"

# RetroArch config (install to user's config dir where retroarch expects it)
mkdir -p "$ROOTFS_DIR/home/archr/.config/retroarch"
cp "$SCRIPT_DIR/config/retroarch.cfg" "$ROOTFS_DIR/home/archr/.config/retroarch/retroarch.cfg"
log "  ✓ RetroArch config installed"

# Archr system config directory
mkdir -p "$ROOTFS_DIR/etc/archr"

# SDL GameController DB for R36S (gpio-keys + adc-joystick)
cp "$SCRIPT_DIR/config/gamecontrollerdb.txt" "$ROOTFS_DIR/etc/archr/gamecontrollerdb.txt"
log "  ✓ GameController DB installed"

# EmulationStation configs
mkdir -p "$ROOTFS_DIR/etc/emulationstation"
if [ -f "$SCRIPT_DIR/config/es_systems.cfg" ]; then
    cp "$SCRIPT_DIR/config/es_systems.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ ES systems config installed"
fi
if [ -f "$SCRIPT_DIR/config/es_input.cfg" ]; then
    cp "$SCRIPT_DIR/config/es_input.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ ES input config installed (gpio-keys + adc-joystick)"
fi

# Battery LED warning script
install -m 755 "$SCRIPT_DIR/scripts/batt_life_warning.py" "$ROOTFS_DIR/usr/local/bin/batt_life_warning.py"
log "  ✓ Battery LED script installed"

# Hotkey daemon (volume/brightness control)
install -m 755 "$SCRIPT_DIR/scripts/archr-hotkeys.py" "$ROOTFS_DIR/usr/local/bin/archr-hotkeys.py"
log "  ✓ Hotkey daemon installed"

# Fix ownership of archr home directory (files installed by root in Step 5)
chown -R 1001:1001 "$ROOTFS_DIR/home/archr"
log "  ✓ archr home ownership fixed (UID 1001)"

#------------------------------------------------------------------------------
# Step 6: Install Kernel and Modules
#------------------------------------------------------------------------------
log ""
log "Step 6: Installing kernel and modules..."

KERNEL_BOOT="$OUTPUT_DIR/boot"
KERNEL_MODULES="$OUTPUT_DIR/modules/lib/modules"

if [ -f "$KERNEL_BOOT/Image" ]; then
    mkdir -p "$ROOTFS_DIR/boot"
    cp "$KERNEL_BOOT/Image" "$ROOTFS_DIR/boot/"
    log "  ✓ Kernel Image installed"

    # Copy R36S DTB
    for dtb in "$KERNEL_BOOT"/*.dtb; do
        [ -f "$dtb" ] && cp "$dtb" "$ROOTFS_DIR/boot/" && \
            log "  ✓ DTB installed: $(basename "$dtb")"
    done
else
    warn "Kernel Image not found. Run build-kernel.sh first!"
fi

if [ -d "$KERNEL_MODULES" ]; then
    cp -r "$KERNEL_MODULES"/* "$ROOTFS_DIR/lib/modules/"
    log "  ✓ Kernel modules installed"

    # Fix kernel version / modules directory mismatch (-dirty suffix)
    # Kernel may report version with -dirty suffix but modules dir lacks it
    for moddir in "$ROOTFS_DIR/lib/modules/"*; do
        [ -d "$moddir" ] || continue
        base=$(basename "$moddir")
        dirty="${base}-dirty"
        if [ ! -e "$ROOTFS_DIR/lib/modules/$dirty" ]; then
            ln -sf "$base" "$ROOTFS_DIR/lib/modules/$dirty"
            log "  ✓ Modules symlink: $dirty -> $base"
        fi
    done
else
    warn "Kernel modules not found. Run build-kernel.sh first!"
fi

#------------------------------------------------------------------------------
# Step 7: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 7: Cleaning up..."

# Remove setup script
rm -f "$ROOTFS_DIR/tmp/setup.sh"

# Remove QEMU
rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

# Unmount
umount -l "$ROOTFS_DIR/run" 2>/dev/null || true
umount -l "$ROOTFS_DIR/sys" 2>/dev/null || true
umount -l "$ROOTFS_DIR/proc" 2>/dev/null || true
umount -l "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
umount -l "$ROOTFS_DIR/dev" 2>/dev/null || true

log "  ✓ Cleanup complete"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== Rootfs Build Complete ==="

ROOTFS_SIZE=$(du -sh "$ROOTFS_DIR" | cut -f1)
log ""
log "Rootfs location: $ROOTFS_DIR"
log "Rootfs size: $ROOTFS_SIZE"
log ""
log "✓ Arch R rootfs ready!"
