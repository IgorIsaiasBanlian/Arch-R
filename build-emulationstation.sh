#!/bin/bash

#==============================================================================
# Arch R - EmulationStation Build Script
#==============================================================================
# Builds EmulationStation-fcamod (christianhaitian fork) for aarch64
# inside the rootfs chroot environment.
#
# This runs AFTER build-rootfs.sh and BEFORE build-image.sh
# Requires: rootfs at output/rootfs with build deps installed
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
ROOTFS_DIR="$OUTPUT_DIR/rootfs"
CACHE_DIR="$SCRIPT_DIR/.cache"
GL4ES_DIR="$OUTPUT_DIR/gl4es"

# EmulationStation source
ES_REPO="https://github.com/christianhaitian/EmulationStation-fcamod.git"
ES_BRANCH="351v"
ES_CACHE="$CACHE_DIR/EmulationStation-fcamod"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[ES-BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[ES-BUILD] WARNING:${NC} $1"; }
error() { echo -e "${RED}[ES-BUILD] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Checks
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (for chroot)"
fi

if [ ! -d "$ROOTFS_DIR/usr" ]; then
    error "Rootfs not found at $ROOTFS_DIR. Run build-rootfs.sh first!"
fi

log "=== Building EmulationStation-fcamod ==="
log "Branch: $ES_BRANCH"

#------------------------------------------------------------------------------
# Step 1: Clone / update EmulationStation source on host
#------------------------------------------------------------------------------
log ""
log "Step 1: Getting EmulationStation source..."

mkdir -p "$CACHE_DIR"

if [ -d "$ES_CACHE/.git" ]; then
    log "  Updating existing clone..."
    cd "$ES_CACHE"
    git fetch origin
    git checkout "$ES_BRANCH"
    git reset --hard "origin/$ES_BRANCH"
    git submodule update --init --recursive
    cd "$SCRIPT_DIR"
else
    log "  Cloning EmulationStation-fcamod..."
    git clone --depth 1 --recurse-submodules -b "$ES_BRANCH" "$ES_REPO" "$ES_CACHE"
fi

log "  ✓ Source ready"

#------------------------------------------------------------------------------
# Step 2: Copy source into rootfs for native build
#------------------------------------------------------------------------------
log ""
log "Step 2: Setting up build environment in rootfs..."

BUILD_DIR="$ROOTFS_DIR/tmp/es-build"
rm -rf "$BUILD_DIR"
cp -a "$ES_CACHE" "$BUILD_DIR"

log "  ✓ Source copied to rootfs"

#------------------------------------------------------------------------------
# Step 2b: Install gl4es into rootfs
#------------------------------------------------------------------------------
log ""
log "Step 2b: Installing gl4es (Desktop GL → GLES 2.0 translation)..."

if [ ! -f "$GL4ES_DIR/libGL.so.1" ]; then
    error "gl4es not found at $GL4ES_DIR. Cross-compile it first!"
fi

# gl4es libraries
install -d "$ROOTFS_DIR/usr/lib/gl4es"
install -m 755 "$GL4ES_DIR/libGL.so.1" "$ROOTFS_DIR/usr/lib/gl4es/"
ln -sf libGL.so.1 "$ROOTFS_DIR/usr/lib/gl4es/libGL.so"
# IMPORTANT: Do NOT install gl4es's libEGL.so.1!
# gl4es EGL wrapper is NOT a full EGL implementation — SDL3 KMSDRM needs real Mesa EGL.
# ES source is patched to request GLES 2.0 context (SDL_GL_CONTEXT_PROFILE_ES),
# and gl4es detects the existing GLES context for its GL→GLES2 translation.
# install -m 755 "$GL4ES_DIR/libEGL.so.1" "$ROOTFS_DIR/usr/lib/gl4es/"  # DISABLED

# unset_preload.so — prevents LD_PRELOAD inheritance to child processes
# Without this, ES subprocesses (battery check, distro version) load gl4es
# and its init messages contaminate stdout → "BAT: 87LIBGL: Initialising gl4es..."
if [ -f "$OUTPUT_DIR/unset_preload.so" ]; then
    install -m 755 "$OUTPUT_DIR/unset_preload.so" "$ROOTFS_DIR/usr/lib/unset_preload.so"
    log "  unset_preload.so installed"
else
    warn "unset_preload.so not found at $OUTPUT_DIR/ — build it with build-gl4es.sh"
fi

# System-level symlinks so cmake FindOpenGL resolves to gl4es
ln -sf gl4es/libGL.so.1 "$ROOTFS_DIR/usr/lib/libGL.so.1"
ln -sf gl4es/libGL.so.1 "$ROOTFS_DIR/usr/lib/libGL.so"

# Desktop GL headers from gl4es (for compilation)
install -d "$ROOTFS_DIR/usr/include/GL"
install -m 644 "$GL4ES_DIR/include/GL/gl.h" "$ROOTFS_DIR/usr/include/GL/"
install -m 644 "$GL4ES_DIR/include/GL/glext.h" "$ROOTFS_DIR/usr/include/GL/"

log "  ✓ gl4es installed (libGL.so.1 + libEGL.so.1 + GL headers)"

#------------------------------------------------------------------------------
# Step 3: Setup chroot
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up chroot..."

# Copy QEMU
if [ -f "/usr/bin/qemu-aarch64-static" ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
else
    error "qemu-aarch64-static not found. Install: sudo apt install qemu-user-static"
fi

# Bind mounts
mount --bind /dev "$ROOTFS_DIR/dev" 2>/dev/null || true
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
mount --bind /proc "$ROOTFS_DIR/proc" 2>/dev/null || true
mount --bind /sys "$ROOTFS_DIR/sys" 2>/dev/null || true
mount --bind /run "$ROOTFS_DIR/run" 2>/dev/null || true
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

log "  ✓ Chroot ready"

#------------------------------------------------------------------------------
# Step 4: Build inside chroot
#------------------------------------------------------------------------------
log ""
log "Step 4: Building EmulationStation inside chroot..."

cat > "$ROOTFS_DIR/tmp/build-es.sh" << 'BUILD_EOF'
#!/bin/bash
set -e

# Disable pacman Landlock sandbox (fails in QEMU chroot)
pacman() { command pacman --disable-sandbox "$@"; }

echo "=== ES Build: Installing dependencies ==="

# Build dependencies (freeimage excluded — built from source below)
# Install base-devel group first (needs separate call for group confirmation)
pacman -S --noconfirm --needed base-devel

# Then install specific build dependencies
pacman -S --noconfirm --needed \
    make \
    gcc \
    cmake \
    git \
    unzip \
    sdl2 \
    sdl2_mixer \
    freetype2 \
    curl \
    rapidjson \
    boost \
    pugixml \
    alsa-lib \
    vlc \
    libdrm \
    mesa

# GPU: Mesa Panfrost (EGL + GLES 2.0+ + GBM for RK3326/Mali-G31)
# gl4es (pre-installed in Step 2b) provides Desktop GL → GLES 2.0 translation
# Mesa provides: libEGL.so, libGLESv2.so (used by gl4es as backend)

# Build FreeImage from source (not available in ALARM aarch64 repos)
if ! pacman -Q freeimage &>/dev/null; then
    echo "=== Building FreeImage from source ==="
    cd /tmp
    rm -rf FreeImage FreeImage3180.zip
    curl -L -o FreeImage3180.zip \
        "https://downloads.sourceforge.net/project/freeimage/Source%20Distribution/3.18.0/FreeImage3180.zip"
    unzip -oq FreeImage3180.zip
    cd FreeImage
    # Patch Makefile for modern GCC compatibility (FreeImage 3.18.0 is old):
    # - C++14: bundled OpenEXR uses throw() specs removed in C++17
    # - unistd.h: bundled ZLib uses lseek/read/write/close without including it
    # - Wno flags: suppress implicit-function-declaration errors in bundled libs
    cat >> Makefile.gnu << 'MKPATCH'
override CFLAGS += -include unistd.h -Wno-implicit-function-declaration -Wno-int-conversion -DPNG_ARM_NEON_OPT=0
override CXXFLAGS += -std=c++14 -include unistd.h -DPNG_ARM_NEON_OPT=0
MKPATCH
    make -j$(nproc)
    make install
    ldconfig
    cd /tmp && rm -rf FreeImage FreeImage3180.zip
    echo "  FreeImage built and installed"
fi

echo "=== ES Build: Rebuilding SDL3 with KMSDRM support ==="

# CRITICAL: ALARM's SDL3 package is built WITHOUT KMSDRM video backend.
# Without KMSDRM, SDL can only use x11/wayland/offscreen/dummy — none work
# on our console-only RK3326. We need to rebuild SDL3 with -DSDL_KMSDRM=ON.
# sdl2-compat (provides libSDL2) wraps SDL3, so it gains KMSDRM automatically.

if ! grep -ao 'kmsdrm' /usr/lib/libSDL3.so* 2>/dev/null | grep -qi kmsdrm; then
    echo "  SDL3 missing KMSDRM support — rebuilding from source..."
    pacman -S --noconfirm --needed cmake meson ninja pkgconf libdrm mesa

    # Get the installed SDL3 version to build the matching release
    SDL3_VER=$(pacman -Q sdl3 2>/dev/null | awk '{print $2}' | cut -d- -f1)
    echo "  System SDL3 version: $SDL3_VER"

    cd /tmp
    rm -rf SDL3-kmsdrm-build

    # Clone matching version (or latest release if version detection fails)
    if [ -n "$SDL3_VER" ]; then
        git clone --depth 1 -b "release-${SDL3_VER}" \
            https://github.com/libsdl-org/SDL.git SDL3-kmsdrm-build 2>/dev/null \
        || git clone --depth 1 https://github.com/libsdl-org/SDL.git SDL3-kmsdrm-build
    else
        git clone --depth 1 https://github.com/libsdl-org/SDL.git SDL3-kmsdrm-build
    fi

    cd SDL3-kmsdrm-build
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DSDL_KMSDRM=ON \
        -DSDL_KMSDRM_SHARED=OFF \
        -DSDL_WAYLAND=OFF \
        -DSDL_X11=OFF \
        -DSDL_VULKAN=OFF \
        -DSDL_PIPEWIRE=OFF \
        -DSDL_PULSEAUDIO=OFF \
        -DSDL_ALSA=ON \
        -DSDL_TESTS=OFF \
        -DSDL_INSTALL_TESTS=OFF

    cmake --build build -j$(nproc)

    # Only replace the shared library (keep headers/pkgconfig from package)
    install -m755 build/libSDL3.so.0.* /usr/lib/
    ldconfig

    cd /tmp && rm -rf SDL3-kmsdrm-build

    # Verify KMSDRM is now available
    if grep -ao 'kmsdrm' /usr/lib/libSDL3.so* 2>/dev/null | grep -qi kmsdrm; then
        echo "  SDL3 rebuilt with KMSDRM support — VERIFIED"
    else
        echo "  WARNING: SDL3 rebuild done but KMSDRM still not found!"
    fi
else
    echo "  SDL3 already has KMSDRM support — skipping rebuild"
fi

echo "=== ES Build: Verifying gl4es ==="

# gl4es (Desktop GL → GLES 2.0 translation) was pre-installed into the rootfs
# by the host script (Step 2b). Verify it's in place.
if [ ! -f /usr/lib/gl4es/libGL.so.1 ]; then
    echo "ERROR: gl4es libGL.so.1 not found! Should be installed by host step."
    exit 1
fi
if [ ! -f /usr/include/GL/gl.h ]; then
    echo "ERROR: GL headers not found! Should be installed by host step."
    exit 1
fi
echo "  gl4es: $(ls -la /usr/lib/gl4es/libGL.so.1)"
echo "  GL headers: $(ls /usr/include/GL/gl.h)"
echo "  System libGL symlink: $(ls -la /usr/lib/libGL.so)"
echo "  ✓ gl4es verified"

echo "=== ES Build: Patching Renderer_GL21.cpp for Mesa/Panfrost ==="

cd /tmp/es-build

# With gl4es, we use Renderer_GL21.cpp (Desktop OpenGL 2.1) instead of
# Renderer_GLES10.cpp. gl4es translates Desktop GL → GLES 2.0 → Panfrost GPU.
# Only 3 patches needed (vs 6 for GLES10):

# Patch 1: Fix CONTEXT_MAJOR_VERSION bug in setupWindow().
# Original code sets MAJOR_VERSION twice. Second should be MINOR_VERSION.
# gl4es reports GL 2.1, so MAJOR=2, MINOR=1 is correct.
sed -i 's/SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 1);/SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);/' \
    es-core/src/renderers/Renderer_GL21.cpp

# Patch 2: Null safety for glGetString in createContext().
# If context creation fails, glGetString returns NULL.
# std::string(NULL) throws std::logic_error → SIGABRT (exit 134).
sed -i 's|std::string glExts = (const char\*)glGetString(GL_EXTENSIONS);|const char* extsPtr = (const char*)glGetString(GL_EXTENSIONS); std::string glExts = extsPtr ? extsPtr : "";|' \
    es-core/src/renderers/Renderer_GL21.cpp

# Patch 3: Re-establish GL context in setSwapInterval().
# setIcon() (called between createContext and setSwapInterval in Renderer.cpp)
# triggers sdl2-compat → SDL3 internal state changes that lose the EGL context.
# Without this fix, ALL subsequent GL rendering fails silently → blank screen.
sed -i '/\t\t\/\/ vsync/i\\t\t// Arch R: Re-establish GL context — setIcon() via sdl2-compat loses it\n\t\tSDL_GL_MakeCurrent(getSDLWindow(), sdlContext);' \
    es-core/src/renderers/Renderer_GL21.cpp

# Patch 4: Request GLES 2.0 context profile in setupWindow().
# Mesa Panfrost doesn't support Desktop GL contexts — only GLES 2.0+.
# Without this, SDL requests Desktop GL 2.1 → eglCreateContext fails → SIGSEGV.
# With GLES 2.0 context, gl4es detects it (eglGetCurrentContext) and translates GL→GLES2.
sed -i '/SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);/i\\t\tSDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);' \
    es-core/src/renderers/Renderer_GL21.cpp

# Change MINOR version: 1 → 0 (GLES 2.0, not GL 2.1)
sed -i 's/SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);/SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);/' \
    es-core/src/renderers/Renderer_GL21.cpp

echo "  Patched Renderer_GL21.cpp (MAJOR/MINOR fix, null safety, GL context restore, GLES profile)"

# Patch 5: Null safety for getShOutput() — popen() can return NULL.
# Without this check, fgets(buffer, size, NULL) → SIGSEGV/SIGABRT.
# GuiMenu calls getShOutput() for battery, volume, brightness, WiFi info.
sed -i 's|FILE\* pipe{popen(mStr.c_str(), "r")};|FILE* pipe{popen(mStr.c_str(), "r")};\n    if (!pipe) return "";|' \
    es-core/src/platform.cpp
echo "  Patched platform.cpp (getShOutput NULL safety)"

echo "=== ES Build: Compiling ==="

# Clean previous build
rm -rf CMakeCache.txt CMakeFiles

# Configure — Desktop OpenGL mode via gl4es
# -DGL=ON forces USE_OPENGL_21 → uses Renderer_GL21.cpp
# cmake FindOpenGL resolves to gl4es's libGL.so (via symlinks set up in Step 2b)
# Rendering pipeline: ES (GL 2.1) → gl4es → GLES 2.0 → Panfrost (Mali-G31)
cmake . \
    -DCMAKE_BUILD_TYPE=Release \
    -DGL=ON \
    -DOpenGL_GL_PREFERENCE=LEGACY \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_CXX_FLAGS="-O2 -march=armv8-a+crc -mtune=cortex-a35 -include cstdint"

# Build
make -j$(nproc)

echo "=== ES Build: Installing ==="

# Install binary
install -d /usr/bin/emulationstation
install -m 755 emulationstation /usr/bin/emulationstation/emulationstation

# Install resources
cp -r resources /usr/bin/emulationstation/

# Create symlink for easy execution
ln -sf /usr/bin/emulationstation/emulationstation /usr/local/bin/emulationstation

echo "=== ES Build: Complete ==="
ls -la /usr/bin/emulationstation/emulationstation
BUILD_EOF

chmod +x "$ROOTFS_DIR/tmp/build-es.sh"
chroot "$ROOTFS_DIR" /tmp/build-es.sh

log "  ✓ EmulationStation built and installed"

#------------------------------------------------------------------------------
# Step 5: Install Arch R configs
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing Arch R EmulationStation configs..."

# es_systems.cfg
if [ -f "$SCRIPT_DIR/config/es_systems.cfg" ]; then
    mkdir -p "$ROOTFS_DIR/etc/emulationstation"
    cp "$SCRIPT_DIR/config/es_systems.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ es_systems.cfg installed"
fi

# ES launch script
install -m 755 "$SCRIPT_DIR/scripts/emulationstation.sh" \
    "$ROOTFS_DIR/usr/bin/emulationstation/emulationstation.sh"
log "  ✓ Launch script installed"

# Note: ES auto-starts via autologin approach (getty@tty1 → .bash_profile → emulationstation.sh)
# The archr-boot-setup.service and autologin are configured in build-rootfs.sh
log "  ✓ ES will auto-start via tty1 autologin (configured in build-rootfs.sh)"

#------------------------------------------------------------------------------
# Step 6: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 6: Cleaning up..."

# Remove build directory (saves ~200MB in rootfs)
rm -rf "$BUILD_DIR"
rm -f "$ROOTFS_DIR/tmp/build-es.sh"

# Remove build-only deps to save space
cat > "$ROOTFS_DIR/tmp/cleanup-es.sh" << 'CLEAN_EOF'
#!/bin/bash
pacman() { command pacman --disable-sandbox "$@"; }
# Remove build-only packages (not needed at runtime)
# KEEP gcc-libs (provides libstdc++.so — needed by everything C++)
for pkg in cmake eigen gcc make binutils autoconf automake \
           fakeroot patch bison flex m4 libtool texinfo; do
    pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
done
pacman -Scc --noconfirm
CLEAN_EOF
chmod +x "$ROOTFS_DIR/tmp/cleanup-es.sh"
chroot "$ROOTFS_DIR" /tmp/cleanup-es.sh
rm -f "$ROOTFS_DIR/tmp/cleanup-es.sh"

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
log "=== EmulationStation Build Complete ==="
log ""
log "Rendering: ES (Desktop GL 2.1) → gl4es → GLES 2.0 → Panfrost (Mali-G31)"
log ""
log "Installed:"
log "  /usr/bin/emulationstation/emulationstation  (binary, -DGL=ON)"
log "  /usr/bin/emulationstation/resources/         (themes/fonts)"
log "  /usr/bin/emulationstation/emulationstation.sh (launch script)"
log "  /usr/local/bin/emulationstation              (symlink)"
log "  /usr/lib/gl4es/libGL.so.1                    (gl4es GL→GLES2 translation)"
log "  /usr/lib/unset_preload.so                    (prevents LD_PRELOAD inheritance)"
log "  (gl4es libEGL.so.1 NOT installed — SDL uses real Mesa EGL)"
log "  /etc/emulationstation/es_systems.cfg         (system config)"
log ""
