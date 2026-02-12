#!/bin/bash

#==============================================================================
# Arch R - EmulationStation Launch Script
# Based on dArkOS emulationstation.sh — handles restart/shutdown signals
#==============================================================================

export HOME=/home/archr
export SDL_ASSERT="always_ignore"
export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# CRITICAL: Force KMSDRM video driver — without this, SDL falls back to
# dummy/offscreen and nothing appears on screen
# Set BOTH SDL2 and SDL3 style env vars — sdl2-compat may not translate all of them
export SDL_VIDEODRIVER=KMSDRM          # SDL2 style (for sdl2-compat)
export SDL_VIDEO_DRIVER=KMSDRM         # SDL3 style (for libSDL3 directly)
# gl4es: Desktop OpenGL → GLES 2.0 translation layer
# ES-fcamod built with -DGL=ON (Renderer_GL21.cpp, Desktop OpenGL 2.1)
# Rendering pipeline: ES (Desktop GL 2.1) → gl4es → GLES 2.0 → Panfrost (Mali-G31)
# gl4es EGL wrapper intercepts eglCreateContext: remaps Desktop GL → GLES 2.0
export LD_LIBRARY_PATH=/usr/lib/gl4es:${LD_LIBRARY_PATH:-}
export SDL_VIDEO_EGL_DRIVER=/usr/lib/gl4es/libEGL.so.1

# gl4es backend configuration
export LIBGL_ES=2                       # Use GLES 2.0 as backend
export LIBGL_GL=21                      # Report OpenGL 2.1 to application
export LIBGL_NPOT=1                     # Non-power-of-two textures (GPU supports it)
export LIBGL_NOERROR=1                  # Suppress GL errors for performance
export LIBGL_SILENTSTUB=1              # Suppress stub function warnings

# Tell gl4es where to find real Mesa libraries (avoid loading itself via LD_LIBRARY_PATH)
export LIBGL_EGL=/usr/lib/libEGL.so.1
export LIBGL_GLES=/usr/lib/libGLESv2.so.2
export SDL_GAMECONTROLLERCONFIG_FILE="/etc/archr/gamecontrollerdb.txt"

# GPU: Mesa auto-detects kmsro (card0=rockchip → panfrost via renderD129)
# DO NOT set MESA_LOADER_DRIVER_OVERRIDE=panfrost — breaks kmsro render-offload!
export LIBGL_ALWAYS_SOFTWARE=0

# Enable SDL verbose logging — shows which video driver is actually used
# Set BOTH SDL2 and SDL3 style logging env vars
export SDL_LOG_PRIORITY=verbose        # SDL2 style
export SDL_LOGGING="*=verbose"         # SDL3 style

# Ensure runtime dir exists
mkdir -p "$XDG_RUNTIME_DIR"

# Set performance governors for gaming (archr has NOPASSWD sudo for perf commands)
sudo /usr/local/bin/perfmax 2>/dev/null

# Ensure DRM/TTY device permissions for game launch (ES needs to release/reacquire)
sudo chmod 666 /dev/tty1 2>/dev/null
sudo chmod 666 /dev/dri/* 2>/dev/null

# Create ES config directory if needed
mkdir -p "$HOME/.emulationstation"

# Link system configs if user doesn't have custom ones
for cfg in es_systems.cfg es_input.cfg; do
    if [ ! -f "$HOME/.emulationstation/$cfg" ] && [ -f "/etc/emulationstation/$cfg" ]; then
        ln -sf "/etc/emulationstation/$cfg" "$HOME/.emulationstation/$cfg"
    fi
done

# Ensure HideWindow is set in existing settings (critical for game launch)
if [ -f "$HOME/.emulationstation/es_settings.cfg" ]; then
    # Fix old <settings> root → <config> (ES-fcamod expects <config> or bare elements)
    if grep -q '<settings>' "$HOME/.emulationstation/es_settings.cfg"; then
        sed -i 's|<settings>|<config>|; s|</settings>|</config>|' \
            "$HOME/.emulationstation/es_settings.cfg"
    fi
    if ! grep -q 'HideWindow' "$HOME/.emulationstation/es_settings.cfg"; then
        sed -i 's|<config>|<config>\n  <bool name="HideWindow" value="true" />|' \
            "$HOME/.emulationstation/es_settings.cfg"
    fi
    # Temporarily force debug log level for KMSDRM debugging
    sed -i 's|"LogLevel" value="[^"]*"|"LogLevel" value="debug"|' \
        "$HOME/.emulationstation/es_settings.cfg"
fi

# Default ES settings for R36S (640x480)
# IMPORTANT: Root element MUST be <config> — ES-fcamod ignores <settings>!
# HideWindow=true is CRITICAL: forces full window teardown before game launch
# Without it, SDL3/sdl2-compat doesn't release DRM master → retroarch can't init display
if [ ! -f "$HOME/.emulationstation/es_settings.cfg" ]; then
    cat > "$HOME/.emulationstation/es_settings.cfg" << 'SETTINGS_EOF'
<?xml version="1.0"?>
<config>
  <int name="MaxVRAM" value="150" />
  <bool name="HideWindow" value="true" />
  <string name="LogLevel" value="debug" />
  <string name="ScreenSaverBehavior" value="black" />
  <string name="TransitionStyle" value="instant" />
  <string name="SaveGamelistsMode" value="on exit" />
  <bool name="DrawClock" value="false" />
  <bool name="QuickSystemSelect" value="false" />
  <string name="CollectionSystemsAuto" value="favorites,recent" />
  <string name="FolderViewMode" value="always" />
</config>
SETTINGS_EOF
fi

# ES directory (where the binary lives)
esdir="$(dirname "$0")"

# Debug log — write to home dir (persistent, readable via sudo from host)
# Also write a copy to /boot if writable (FAT32, easy to read from PC)
DEBUGLOG="$HOME/es-debug.log"

# Comprehensive diagnostic logging
{
    echo "=========================================="
    echo "Arch R ES Debug Log - $(date)"
    echo "=========================================="
    echo ""
    echo "--- Environment ---"
    echo "User: $(id)"
    echo "TTY: $(tty)"
    echo "PWD: $(pwd)"
    echo "SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
    echo "SDL_VIDEO_EGL_DRIVER=$SDL_VIDEO_EGL_DRIVER"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo "LIBGL_ES=$LIBGL_ES"
    echo "LIBGL_GL=$LIBGL_GL"
    echo "LIBGL_EGL=$LIBGL_EGL"
    echo "LIBGL_GLES=$LIBGL_GLES"
    echo "MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-(not set, kmsro auto)}"
    echo ""
    echo "--- DRI Devices ---"
    ls -la /dev/dri/ 2>&1
    echo ""
    echo "--- DRM Device Info ---"
    for card in /dev/dri/card*; do
        echo "Device: $card"
        echo "  readable: $(test -r "$card" && echo YES || echo NO)"
        echo "  writable: $(test -w "$card" && echo YES || echo NO)"
        # Show which driver this card uses
        if [ -d "/sys/class/drm/$(basename $card)/device/driver" ]; then
            echo "  driver: $(basename $(readlink /sys/class/drm/$(basename $card)/device/driver))"
        fi
        # Show connectors
        for conn in /sys/class/drm/$(basename $card)-*/status; do
            if [ -f "$conn" ]; then
                connname=$(basename $(dirname "$conn"))
                echo "  connector: $connname = $(cat $conn)"
            fi
        done
    done
    echo ""
    echo "--- VT Info ---"
    echo "Current VT: $(sudo cat /sys/class/tty/tty0/active 2>/dev/null || echo unknown)"
    echo "tty1 permissions: $(ls -la /dev/tty1 2>&1)"
    echo ""
    echo "--- SDL Libraries ---"
    echo "libSDL2: $(ls -la /usr/lib/libSDL2* 2>&1)"
    echo "libSDL3: $(ls -la /usr/lib/libSDL3* 2>&1)"
    echo ""
    echo "--- KMSDRM in SDL ---"
    # Use grep -a (binary mode) instead of strings — binutils may not be installed
    grep -ao 'KMSDRM[_A-Z]*' /usr/lib/libSDL3.so.0.* 2>/dev/null | sort -u | head -5
    echo "SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
    echo "SDL_VIDEO_DRIVER=$SDL_VIDEO_DRIVER"
    echo ""
    echo "--- gl4es Libraries ---"
    echo "gl4es libGL: $(ls -la /usr/lib/gl4es/libGL.so* 2>&1)"
    echo "gl4es libEGL: $(ls -la /usr/lib/gl4es/libEGL.so* 2>&1)"
    echo ""
    echo "--- Mesa/System Libraries ---"
    echo "Mesa libEGL: $(ls -la /usr/lib/libEGL.so* 2>&1)"
    echo "libGLESv2: $(ls -la /usr/lib/libGLESv2.so* 2>&1)"
    echo "libgbm: $(ls -la /usr/lib/libgbm.so* 2>&1)"
    echo "Panfrost DRI: $(ls -la /usr/lib/dri/panfrost_dri.so 2>&1)"
    echo "System libGL: $(ls -la /usr/lib/libGL.so* 2>&1)"
    echo ""
    echo "--- GPU Kernel Driver Status ---"
    echo "Panfrost loaded:"
    if [ -d /sys/bus/platform/drivers/panfrost ]; then
        echo "  driver: YES"
        ls /sys/bus/platform/drivers/panfrost/ 2>&1
    else
        echo "  driver: NOT LOADED!"
    fi
    echo "Mali Midgard loaded:"
    if [ -d /sys/bus/platform/drivers/mali ]; then
        echo "  driver: YES (CONFLICT!)"
        ls /sys/bus/platform/drivers/mali/ 2>&1
    else
        echo "  driver: no (good)"
    fi
    echo "renderD128 driver:"
    if [ -L /sys/class/drm/renderD128/device/driver ]; then
        echo "  $(basename $(readlink /sys/class/drm/renderD128/device/driver))"
    else
        echo "  NOT FOUND!"
    fi
    echo "GPU device:"
    for dev in /sys/bus/platform/devices/*.gpu /sys/bus/platform/devices/*mali*; do
        if [ -e "$dev" ]; then
            echo "  $dev"
            if [ -f "$dev/of_node/compatible" ]; then
                echo "    compatible: $(cat $dev/of_node/compatible | tr '\0' ' ')"
            fi
            if [ -L "$dev/driver" ]; then
                echo "    bound to: $(basename $(readlink $dev/driver))"
            else
                echo "    bound to: NONE (no driver bound!)"
            fi
        fi
    done 2>/dev/null
    echo "Kernel config GPU:"
    zcat /proc/config.gz 2>/dev/null | grep -E 'PANFROST|MALI' | head -10
    echo ""
    echo "--- dmesg GPU/Panfrost ---"
    sudo dmesg 2>/dev/null | grep -iE 'panfrost|mali|gpu|drm.*ff400|bifrost' | head -30
    echo ""
    echo "--- dmesg IOMMU ---"
    sudo dmesg 2>/dev/null | grep -iE 'iommu|rockchip-iommu' | head -10
    echo ""
    echo "--- dmesg errors/failures ---"
    sudo dmesg 2>/dev/null | grep -iE 'fatal|failed|error.*gpu|error.*mali|error.*panfrost' | head -10
    echo ""
    echo "--- es_settings.cfg ---"
    cat "$HOME/.emulationstation/es_settings.cfg" 2>&1
    echo ""
    echo "--- VT Graphics Mode Test ---"
    # Test if we can switch VT to graphics mode (hides console text)
    # This is what SDL KMSDRM does internally. If this fails, KMSDRM can't work.
    python3 -c "
import fcntl, os, time
try:
    fd = os.open('/dev/tty', os.O_RDWR)
    KDGETMODE = 0x4B3B
    KDSETMODE = 0x4B3A
    KD_TEXT = 0
    KD_GRAPHICS = 1
    import struct
    mode = struct.unpack('i', fcntl.ioctl(fd, KDGETMODE, b'\x00\x00\x00\x00'))[0]
    print(f'Current VT mode: {\"TEXT\" if mode == 0 else \"GRAPHICS\" if mode == 1 else mode}')
    fcntl.ioctl(fd, KDSETMODE, KD_GRAPHICS)
    print('Set VT to GRAPHICS mode: OK')
    fcntl.ioctl(fd, KDSETMODE, KD_TEXT)
    print('Restored VT to TEXT mode: OK')
    os.close(fd)
except Exception as e:
    print(f'VT graphics mode test FAILED: {e}')
" 2>&1
    echo ""
    echo "=========================================="
    echo "Starting EmulationStation..."
    echo "=========================================="
} > "$DEBUGLOG" 2>&1

# Copy debug log to /boot (FAT32, easy to read from PC) — needs sudo
sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null

# KMSDRM + GL context diagnostic — runs in single SDL session, safe for boot
if [ -f "$esdir/test-kmsdrm.py" ]; then
    echo "--- KMSDRM GL Diagnostic ---" >> "$DEBUGLOG"
    timeout 30 python3 "$esdir/test-kmsdrm.py" >> "$DEBUGLOG" 2>&1 || true
    echo "Test exit code: $?" >> "$DEBUGLOG"
    echo "" >> "$DEBUGLOG"
    sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null
fi

# Panfrost GPU module test — load and capture crash trace for debugging
# Safe: module crash won't panic since it's not built-in
echo "--- Panfrost Module Test ---" >> "$DEBUGLOG"
KVER=$(uname -r)
echo "  Kernel: $KVER" >> "$DEBUGLOG"
echo "  Module dirs: $(ls /lib/modules/ 2>&1)" >> "$DEBUGLOG"
PANFROST_KO="/lib/modules/$KVER/kernel/drivers/gpu/drm/panfrost/panfrost.ko"
if [ -f "$PANFROST_KO" ]; then
    echo "  panfrost.ko: FOUND ($PANFROST_KO)" >> "$DEBUGLOG"
elif [ -f "${PANFROST_KO}.zst" ]; then
    echo "  panfrost.ko.zst: FOUND (compressed)" >> "$DEBUGLOG"
    PANFROST_KO="${PANFROST_KO}.zst"
elif [ -f "${PANFROST_KO}.xz" ]; then
    echo "  panfrost.ko.xz: FOUND (compressed)" >> "$DEBUGLOG"
    PANFROST_KO="${PANFROST_KO}.xz"
else
    echo "  panfrost.ko: NOT FOUND at $PANFROST_KO" >> "$DEBUGLOG"
    echo "  Looking for panfrost anywhere..." >> "$DEBUGLOG"
    find /lib/modules/ -name 'panfrost*' 2>/dev/null >> "$DEBUGLOG"
fi
echo "  modules.dep exists: $(test -f /lib/modules/$KVER/modules.dep && echo YES || echo NO)" >> "$DEBUGLOG"
echo "  depmod panfrost entries:" >> "$DEBUGLOG"
grep panfrost /lib/modules/$KVER/modules.dep 2>/dev/null >> "$DEBUGLOG" || echo "  (none)" >> "$DEBUGLOG"

if lsmod 2>/dev/null | grep -q panfrost; then
    echo "  panfrost already loaded" >> "$DEBUGLOG"
else
    # Run depmod first in case it wasn't run after module install
    sudo depmod -a 2>> "$DEBUGLOG"
    echo "  Loading panfrost module (verbose)..." >> "$DEBUGLOG"
    sudo modprobe -v panfrost >> "$DEBUGLOG" 2>&1
    MODPROBE_RET=$?
    echo "  modprobe exit code: $MODPROBE_RET" >> "$DEBUGLOG"
    sleep 2
    echo "  lsmod panfrost: $(lsmod 2>/dev/null | grep panfrost || echo 'NOT LOADED')" >> "$DEBUGLOG"
fi
echo "  --- dmesg panfrost messages ---" >> "$DEBUGLOG"
sudo dmesg 2>/dev/null | grep -iE 'panfrost|gpu.*ff400' >> "$DEBUGLOG"
echo "" >> "$DEBUGLOG"
# Check if GPU bound successfully
echo "  --- GPU binding status ---" >> "$DEBUGLOG"
for dev in /sys/bus/platform/devices/*.gpu; do
    if [ -e "$dev" ]; then
        if [ -L "$dev/driver" ]; then
            echo "  $(basename $dev) bound to: $(basename $(readlink $dev/driver))" >> "$DEBUGLOG"
        else
            echo "  $(basename $dev) bound to: NONE" >> "$DEBUGLOG"
        fi
    fi
done 2>/dev/null
if [ -L /sys/class/drm/renderD128/device/driver ]; then
    echo "  renderD128: $(basename $(readlink /sys/class/drm/renderD128/device/driver))" >> "$DEBUGLOG"
fi
echo "" >> "$DEBUGLOG"
sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null

# Main loop — handles ES restart/shutdown signals (like dArkOS)
# ES uses system() to launch games — it blocks, does NOT exit.
# ES only exits for: settings restart, reboot, shutdown, or crash.
while true; do
    rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown

    # Run ES — output goes to tty and also captured to debug log
    "$esdir/emulationstation" "$@" 2>&1 | tee -a "$DEBUGLOG"
    ret=${PIPESTATUS[0]}

    echo "ES exited with code: $ret" >> "$DEBUGLOG"
    # Save debug log to /boot for easy access from PC
    sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null

    # ES requested restart (settings changed, language changed, etc.)
    [ -f /tmp/es-restart ] && continue

    # ES requested system reboot
    if [ -f /tmp/es-sysrestart ]; then
        rm -f /tmp/es-sysrestart
        systemctl reboot
        break
    fi

    # ES requested shutdown
    if [ -f /tmp/es-shutdown ]; then
        rm -f /tmp/es-shutdown
        systemctl poweroff
        break
    fi

    # ES exited without signal — don't restart
    break
done

# Restore normal governor on exit
sudo /usr/local/bin/perfnorm 2>/dev/null

exit $ret
