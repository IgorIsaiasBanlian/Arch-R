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
#
# How it works (without gl4es EGL wrapper):
#   1. ES setupWindow() requests GLES 2.0 context (SDL_GL_CONTEXT_PROFILE_ES patch)
#   2. SDL3 KMSDRM creates GLES 2.0 context via Mesa EGL → Panfrost GPU
#   3. ES calls Desktop GL functions → gl4es libGL.so.1 intercepts them
#   4. gl4es detects the GLES 2.0 context (eglGetCurrentContext) and translates GL→GLES2
#
# DO NOT set SDL_VIDEO_EGL_DRIVER — gl4es's libEGL.so is NOT a full EGL implementation.
# SDL3 KMSDRM needs real Mesa EGL for GBM display/surface init.
# gl4es libEGL.so.1 must NOT be in /usr/lib/gl4es/ either — LD_LIBRARY_PATH would
# shadow Mesa's libEGL.so.1, causing the same crash.
export LD_LIBRARY_PATH=/usr/lib/gl4es:${LD_LIBRARY_PATH:-}

# gl4es loading: LD_PRELOAD forces gl4es libGL.so.1 to load (cmake links against
# libOpenGL.so/libglvnd, not libGL.so.1). unset_preload.so removes LD_PRELOAD from
# the environment AFTER the dynamic linker loads both libraries — this way gl4es is
# loaded in ES's process, but child processes (system(), popen()) don't inherit it.
# Without this: every subprocess (battery check, distro version, brightnessctl) loads
# gl4es → init messages contaminate stdout → "BAT: 87LIBGL: Initialising gl4es..."
ES_LD_PRELOAD="/usr/lib/gl4es/libGL.so.1 /usr/lib/unset_preload.so"

# gl4es backend configuration
export LIBGL_FB=0                       # CRITICAL: Don't create own framebuffer/EGL context
                                        # Without this, gl4es tries eglGetDisplay(DEFAULT) which
                                        # fails on KMSDRM → renders to its own dead context → black screen
                                        # With FB=0, gl4es uses SDL's existing GLES context
export LIBGL_ES=2                       # Use GLES 2.0 as backend
export LIBGL_GL=21                      # Report OpenGL 2.1 to application
export LIBGL_NPOT=3                     # Full NPOT support (1=limited, 3=full — avoids texture rescaling)
export LIBGL_NOERROR=1                  # Suppress GL errors for performance
export LIBGL_SILENTSTUB=1              # Suppress stub function warnings
export LIBGL_FASTMATH=1                 # Use fast math approximations
export LIBGL_USEVBO=1                   # Use VBOs for vertex data (faster than immediate mode)
export LIBGL_TEXCOPY=1                  # Optimize texture uploads
export LIBGL_NOTEST=1                   # Skip EGL hardware extension query — use GLES 2.0 defaults
                                        # MUST be 1: gl4es eglInitialize floods on KMSDRM even with
                                        # patched binary (tested=1 early not preventing re-entry)
                                        # NOTEST=1 is safe: npot=1, fbo=1, blendcolor=1 (GLES 2.0 standard)
# gl4es debug: 0=silent, 1=init+errors, 2=verbose (performance killer!)
export LIBGL_DEBUG=0                    # PRODUCTION: silent (1 for diagnostics)

# Tell gl4es where to find real Mesa libraries (avoid loading itself via LD_LIBRARY_PATH)
export LIBGL_EGL=/usr/lib/libEGL.so.1
export LIBGL_GLES=/usr/lib/libGLESv2.so.2
export SDL_GAMECONTROLLERCONFIG_FILE="/etc/archr/gamecontrollerdb.txt"

# GPU: Mesa auto-detects kmsro (card0=rockchip → panfrost via renderD129)
# DO NOT set MESA_LOADER_DRIVER_OVERRIDE=panfrost — breaks kmsro render-offload!
export LIBGL_ALWAYS_SOFTWARE=0

# SDL logging: only errors (verbose was for KMSDRM debugging, now confirmed working)
export SDL_LOG_PRIORITY=error          # SDL2 style
export SDL_LOGGING="*=error"           # SDL3 style

# DO NOT set MESA_NO_ERROR=1 — gl4es makes some invalid GLES calls during
# Desktop GL → GLES translation. With no-error mode, Mesa segfaults instead of
# returning GL_INVALID_OPERATION gracefully. Confirmed: SIGSEGV (exit 139).
# gl4es already has LIBGL_NOERROR=1 which suppresses errors on the gl4es side.

# Mesa shader cache — speeds up subsequent launches by caching compiled shaders
export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
mkdir -p "$MESA_SHADER_CACHE_DIR" 2>/dev/null

# Ensure runtime dir exists
mkdir -p "$XDG_RUNTIME_DIR"

# Suppress gl4es drirc warnings (per-system and per-user)
if [ ! -f /etc/drirc ]; then
    echo '<?xml version="1.0"?><driconf/>' | sudo tee /etc/drirc >/dev/null 2>/dev/null
fi
if [ ! -f "$HOME/.drirc" ]; then
    echo '<?xml version="1.0"?><driconf/>' > "$HOME/.drirc" 2>/dev/null
fi

# Set performance governors for gaming (archr has NOPASSWD sudo for perf commands)
sudo /usr/local/bin/perfmax 2>&1 || true

# Audio initialization: rk817 BSP codec starts with path OFF
# Must set Playback Path to SPK for speaker output, then set volume level
# DAC Playback Volume range: 0-255 (inverted), 80% ≈ -20dB (comfortable level)
amixer -q sset 'Playback Path' SPK 2>/dev/null
amixer -q sset 'DAC Playback Volume' 80% 2>/dev/null

# Restore saved brightness (or set default 50%)
BRIGHT_SAVE="$HOME/.config/archr/brightness"
if [ -f "$BRIGHT_SAVE" ]; then
    brightnessctl -q s "$(cat "$BRIGHT_SAVE")" 2>/dev/null
fi

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
    sed -i 's|"LogLevel" value="[^"]*"|"LogLevel" value="warning"|' \
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
  <string name="LogLevel" value="warning" />
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

# Compact diagnostic logging — Panfrost/KMSDRM/VT already confirmed working
{
    echo "=========================================="
    echo "Arch R ES Debug Log - $(date)"
    echo "=========================================="
    echo ""
    echo "--- Environment ---"
    echo "User: $(id)"
    echo "TTY: $(tty)"
    echo "SDL_VIDEODRIVER=$SDL_VIDEODRIVER"
    echo "SDL_VIDEO_DRIVER=$SDL_VIDEO_DRIVER"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo "ES_LD_PRELOAD=$ES_LD_PRELOAD (applied only to ES binary)"
    echo "LIBGL_FB=$LIBGL_FB"
    echo "LIBGL_ES=$LIBGL_ES"
    echo "LIBGL_GL=$LIBGL_GL"
    echo "LIBGL_EGL=$LIBGL_EGL"
    echo "LIBGL_GLES=$LIBGL_GLES"
    echo "LIBGL_DEBUG=$LIBGL_DEBUG"
    echo ""
    echo "--- DRI Devices ---"
    ls -la /dev/dri/ 2>&1
    echo ""
    echo "--- GPU Status ---"
    for dev in /sys/bus/platform/devices/*.gpu; do
        if [ -e "$dev" ]; then
            drv="NONE"
            [ -L "$dev/driver" ] && drv=$(basename $(readlink "$dev/driver"))
            echo "  $(basename "$dev"): $drv"
        fi
    done 2>/dev/null
    lsmod 2>/dev/null | grep -E 'panfrost|mali' || echo "  (no GPU modules loaded)"
    echo ""
    echo "--- CPU/GPU Governors ---"
    echo "  CPU governor: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>&1)"
    echo "  CPU freq: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>&1) kHz"
    echo "  CPU max: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>&1) kHz"
    echo "  GPU governor: $(cat /sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/governor 2>&1)"
    echo "  GPU freq: $(cat /sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/cur_freq 2>&1) Hz"
    echo ""
    echo "--- gl4es ---"
    ls -la /usr/lib/gl4es/ 2>&1
    echo ""
    echo "--- Audio Status ---"
    if [ -d /dev/snd ]; then
        ls -la /dev/snd/ 2>&1
        echo "  ALSA cards:"
        cat /proc/asound/cards 2>&1 || echo "  (no cards)"
    else
        echo "  /dev/snd/ does NOT exist — no ALSA devices!"
    fi
    echo "  Battery: $(cat /sys/class/power_supply/battery/capacity 2>&1)%"
    echo "  Charging: $(cat /sys/class/power_supply/battery/status 2>&1)"
    echo "  Power supply devices:"
    ls /sys/class/power_supply/ 2>&1 || echo "  (none)"
    echo ""
    echo "--- Audio/Codec dmesg ---"
    dmesg 2>/dev/null | grep -iE 'rk817|i2s|sound|audio|codec|asoc|snd' | tail -20
    echo ""
    echo "--- es_settings.cfg ---"
    cat "$HOME/.emulationstation/es_settings.cfg" 2>&1
    echo ""
    echo "=========================================="
    echo "Starting EmulationStation..."
    echo "=========================================="
} > "$DEBUGLOG" 2>&1

# Copy debug log to /boot (FAT32, easy to read from PC) — needs sudo
sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null

# Ensure Panfrost module is loaded (needed for GPU acceleration)
if ! lsmod 2>/dev/null | grep -q panfrost; then
    echo "--- Loading Panfrost module ---" >> "$DEBUGLOG"
    sudo depmod -a 2>> "$DEBUGLOG"
    sudo modprobe -v panfrost >> "$DEBUGLOG" 2>&1
    sleep 1
fi
echo "Panfrost: $(lsmod 2>/dev/null | grep panfrost | head -1 || echo 'NOT LOADED')" >> "$DEBUGLOG"
echo "" >> "$DEBUGLOG"
sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null

# Main loop — handles ES restart/shutdown signals (like dArkOS)
# ES uses system() to launch games — it blocks, does NOT exit.
# ES only exits for: settings restart, reboot, shutdown, or crash.
while true; do
    rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown

    # Background: check which GPU driver ES actually loaded (definitive panfrost vs llvmpipe)
    # Runs after 3s delay, finds ES by process name, checks /proc/maps
    {
        sleep 3
        ES_PID=$(pgrep -x emulationstation 2>/dev/null | head -1)
        if [ -n "$ES_PID" ] && [ -r "/proc/$ES_PID/maps" ]; then
            echo "" >> "$DEBUGLOG"
            echo "--- GPU Driver Check (PID $ES_PID) ---" >> "$DEBUGLOG"
            if grep -q "panfrost" /proc/$ES_PID/maps 2>/dev/null; then
                echo "  CONFIRMED: Panfrost GPU (hardware accelerated)" >> "$DEBUGLOG"
            elif grep -q "llvmpipe\|swrast" /proc/$ES_PID/maps 2>/dev/null; then
                echo "  WARNING: llvmpipe/swrast (SOFTWARE rendering — slow!)" >> "$DEBUGLOG"
            else
                echo "  Unknown GPU driver — check /proc/$ES_PID/maps manually" >> "$DEBUGLOG"
            fi
            grep -E "panfrost|llvmpipe|swrast|gl4es|libGL" /proc/$ES_PID/maps >> "$DEBUGLOG" 2>/dev/null
            sudo cp "$DEBUGLOG" /boot/es-debug.log 2>/dev/null
        fi
    } &

    # Run ES — output captured to debug log (no tee: tty1 is KMSDRM, text invisible)
    # IMPORTANT: Removing the pipe to tee eliminates I/O bottleneck on slow microSD.
    # With tee, EVERY line of gl4es/Mesa output blocks ES until tee writes to SD card.
    # LD_PRELOAD applies ONLY to ES process — forces gl4es libGL.so.1 to load
    # so its GL symbols override libglvnd's dispatch (cmake linked against libOpenGL.so)
    LD_PRELOAD="$ES_LD_PRELOAD" "$esdir/emulationstation" "$@" >> "$DEBUGLOG" 2>&1
    ret=$?

    echo "ES exited with code: $ret" >> "$DEBUGLOG"
    # Capture ES internal log (has GL extensions, system info)
    if [ -f "$HOME/.emulationstation/es_log.txt" ]; then
        echo "" >> "$DEBUGLOG"
        echo "--- ES Internal Log (es_log.txt) ---" >> "$DEBUGLOG"
        cat "$HOME/.emulationstation/es_log.txt" >> "$DEBUGLOG" 2>&1
    fi
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
