#!/bin/bash

#==============================================================================
# Arch R - Build gl4es (Desktop GL → GLES 2.0 translation layer)
#==============================================================================
# Cross-compiles gl4es for aarch64 (RK3326/Cortex-A35) with KMSDRM fix.
#
# Patch: hardext.c — use eglGetCurrentDisplay() for extension queries on KMSDRM.
# Without this, gl4es tries eglGetDisplay(EGL_DEFAULT_DISPLAY) which fails
# on KMSDRM (no X11/Wayland default display) → extensions unavailable →
# all GL calls rendered blind → black screen.
#
# Output: output/gl4es/libGL.so.1
# Usage: ./build-gl4es.sh
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output/gl4es"
BUILD_DIR="/tmp/gl4es-build"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
log() { echo -e "${GREEN}[gl4es]${NC} $1"; }
error() { echo -e "${RED}[gl4es] ERROR:${NC} $1"; exit 1; }

# Check cross-compiler
if ! command -v aarch64-linux-gnu-gcc &>/dev/null; then
    error "Cross-compiler not found. Install: sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
fi

#------------------------------------------------------------------------------
# Step 1: Clone gl4es
#------------------------------------------------------------------------------
log "Step 1: Cloning gl4es..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

git clone --depth 1 https://github.com/ptitSeb/gl4es.git .
log "  Cloned $(git log --oneline -1)"

#------------------------------------------------------------------------------
# Step 2: Patch hardext.c — fix eglInitialize on KMSDRM
#------------------------------------------------------------------------------
log ""
log "Step 2: Patching hardext.c for KMSDRM..."

# The bug: GetHardwareExtensions() calls eglGetDisplay(EGL_DEFAULT_DISPLAY)
# which fails on KMSDRM (no default display). It retries every frame →
# hundreds of errors, no extensions, black screen.
#
# Fix strategy (Python patcher for reliability — sed was silently failing):
#   1. Set tested=1 IMMEDIATELY after the guard check — function runs at most ONCE
#   2. Try eglGetCurrentDisplay() first (use SDL's display if available)
#   3. On eglInitialize failure, just return (tested already 1)
#   4. Add query_extensions: label for goto from Fix 2

log "Patching hardext.c with Python patcher..."

HARDEXT="src/glx/hardext.c"
if [ ! -f "$HARDEXT" ]; then
    error "hardext.c not found at $HARDEXT"
fi

python3 << 'PYEOF'
import sys

with open("src/glx/hardext.c", "r") as f:
    lines = f.readlines()

output = []
fixes = {"tested_early": False, "eglGetCurrentDisplay": False, "query_label": False}

i = 0
while i < len(lines):
    line = lines[i]

    # Fix 1: Set tested=1 right after "if(tested) return;" guard
    # This ensures the function ONLY runs once, regardless of failure path
    if not fixes["tested_early"] and "if(tested) return;" in line:
        output.append(line)
        output.append("    tested = 1;  // KMSDRM fix: set immediately — never retry\n")
        fixes["tested_early"] = True
        i += 1
        continue

    # Fix 2: Add eglGetCurrentDisplay() check before GBM/DEFAULT path
    # Insert after "static EGLConfig pbufConfigs[1];" line
    if not fixes["eglGetCurrentDisplay"] and "static EGLConfig pbufConfigs" in line:
        output.append(line)
        # Skip blank line if present
        if i+1 < len(lines) and lines[i+1].strip() == "":
            output.append(lines[i+1])
            i += 1
        output.append("""
    // KMSDRM fix: try existing EGL display from SDL first.
    // On KMSDRM, eglGetDisplay(DEFAULT) fails (no X11/Wayland).
    // SDL already has a valid EGL display via eglGetPlatformDisplay(GBM).
    LOAD_EGL(eglGetCurrentDisplay);
    if (egl_eglGetCurrentDisplay) {
        eglDisplay = egl_eglGetCurrentDisplay();
        if (eglDisplay != EGL_NO_DISPLAY) {
            SHUT_LOGD("Using existing EGL display from application context\\n");
            goto query_extensions;
        }
    }

""")
        fixes["eglGetCurrentDisplay"] = True
        i += 1
        continue

    # Fix 3: Add query_extensions: label before first LOAD_GLES(glGetString)
    if not fixes["query_label"] and "LOAD_GLES(glGetString)" in line:
        output.append("    query_extensions:\n")
        output.append(line)
        fixes["query_label"] = True
        i += 1
        continue

    output.append(line)
    i += 1

# Verify all fixes were applied
for name, applied in fixes.items():
    if not applied:
        print(f"ERROR: Fix '{name}' was NOT applied!", file=sys.stderr)
        sys.exit(1)

with open("src/glx/hardext.c", "w") as f:
    f.writelines(output)

print(f"All {len(fixes)} fixes applied successfully")
PYEOF

if [ $? -ne 0 ]; then
    error "Python patcher failed!"
fi

# Verify patches in source
log "  Verifying patches..."
if grep -q "tested = 1;  // KMSDRM fix: set immediately" "$HARDEXT"; then
    log "  Fix 1: tested=1 early — OK"
else
    error "Fix 1 (tested early) not found in patched source"
fi
if grep -q "LOAD_EGL(eglGetCurrentDisplay)" "$HARDEXT"; then
    log "  Fix 2: eglGetCurrentDisplay check — OK"
else
    error "Fix 2 (eglGetCurrentDisplay) not found in patched source"
fi
if grep -q "query_extensions:" "$HARDEXT"; then
    log "  Fix 3: query_extensions label — OK"
else
    error "Fix 3 (query_extensions label) not found in patched source"
fi

#------------------------------------------------------------------------------
# Step 3: Create fake pkg-config files for cross-compilation
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up cross-compilation environment..."

FAKE_PC_DIR="$BUILD_DIR/fake-pkgconfig"
mkdir -p "$FAKE_PC_DIR"

# gl4es only needs headers and link flags — actual libs are on the target
for lib in egl gbm libdrm; do
    cat > "$FAKE_PC_DIR/$lib.pc" << PCEOF
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: $lib
Description: $lib (fake for cross-compile)
Version: 1.0.0
Libs: -l${lib}
Cflags: -I\${includedir}
PCEOF
done

export PKG_CONFIG_PATH="$FAKE_PC_DIR"
export PKG_CONFIG_LIBDIR="$FAKE_PC_DIR"

#------------------------------------------------------------------------------
# Step 4: Cross-compile gl4es
#------------------------------------------------------------------------------
log ""
log "Step 4: Cross-compiling gl4es (GOA_CLONE=ON)..."

mkdir -p build && cd build

cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../CMakeCM/toolchains/aarch64-linux-gnu.cmake \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
    -DGOA_CLONE=ON \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_FLAGS="-I/usr/include/libdrm" \
    2>&1 || {
        # If toolchain file doesn't exist, try without it
        log "  Toolchain file not found, using manual flags..."
        cd .. && rm -rf build && mkdir build && cd build
        cmake .. \
            -DCMAKE_SYSTEM_NAME=Linux \
            -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
            -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
            -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
            -DGOA_CLONE=ON \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_C_FLAGS="-I/usr/include/libdrm"
    }

make -j$(nproc)

#------------------------------------------------------------------------------
# Step 5: Install to output directory
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing to output/gl4es/..."

mkdir -p "$OUTPUT_DIR"

# Find the built library (cmake outputs to $BUILD_DIR/lib/ with GOA_CLONE)
GL4ES_LIB=$(find "$BUILD_DIR" -name "libGL.so.1" -type f 2>/dev/null | head -1)
if [ -z "$GL4ES_LIB" ]; then
    GL4ES_LIB=$(find "$BUILD_DIR" -name "libGL.so*" -type f 2>/dev/null | head -1)
fi

if [ -z "$GL4ES_LIB" ]; then
    error "Built libGL.so.1 not found!"
fi

cp "$GL4ES_LIB" "$OUTPUT_DIR/libGL.so.1"

# Verify it's aarch64
FILE_TYPE=$(file "$OUTPUT_DIR/libGL.so.1")
if echo "$FILE_TYPE" | grep -q "aarch64"; then
    log "  libGL.so.1: OK (aarch64, $(du -h "$OUTPUT_DIR/libGL.so.1" | cut -f1))"
else
    error "Wrong architecture: $FILE_TYPE"
fi

# Verify patch is in binary
if grep -ao "Using existing EGL display" "$OUTPUT_DIR/libGL.so.1" >/dev/null 2>&1; then
    log "  KMSDRM patch: verified in binary"
else
    log "  WARNING: patch string not found in binary (may be optimized out)"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Step 6: Build unset_preload.so (prevents LD_PRELOAD inheritance)
#------------------------------------------------------------------------------
log ""
log "Step 6: Building unset_preload.so..."

# ES uses system()/popen() to run shell commands (battery %, distro version).
# With LD_PRELOAD=gl4es, every subprocess loads gl4es which prints init messages
# to stdout. ES captures these as command output → "BAT: 87LIBGL: Initialising..."
# unset_preload.so's constructor removes LD_PRELOAD from the environment AFTER
# the dynamic linker has loaded all preloaded libraries (gl4es is already mapped).
UNSET_SRC="$SCRIPT_DIR/scripts/unset_preload.c"
UNSET_OUT="$SCRIPT_DIR/output/unset_preload.so"

if [ ! -f "$UNSET_SRC" ]; then
    error "unset_preload.c not found at $UNSET_SRC"
fi

aarch64-linux-gnu-gcc -shared -O2 -o "$UNSET_OUT" "$UNSET_SRC"
aarch64-linux-gnu-strip "$UNSET_OUT"

FILE_TYPE=$(file "$UNSET_OUT")
if echo "$FILE_TYPE" | grep -q "aarch64"; then
    log "  unset_preload.so: OK (aarch64, $(du -h "$UNSET_OUT" | cut -f1))"
else
    error "Wrong architecture: $FILE_TYPE"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== gl4es Build Complete ==="
log ""
log "  Output: $OUTPUT_DIR/libGL.so.1"
log "  Output: $SCRIPT_DIR/output/unset_preload.so"
log "  Patch: eglGetCurrentDisplay() for KMSDRM extension queries"
log "  Config: GOA_CLONE=ON (Cortex-A35, NOX11, GBM)"
log ""
log "Next: copy to SD card:"
log "  sudo cp output/gl4es/libGL.so.1 /media/dgateles/ROOTFS/usr/lib/gl4es/libGL.so.1"
log "  sudo cp output/unset_preload.so /media/dgateles/ROOTFS/usr/lib/unset_preload.so"
