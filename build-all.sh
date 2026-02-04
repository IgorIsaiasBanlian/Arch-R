#!/bin/bash

#==============================================================================
# Arch R - Master Build Script
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment
if [ -f "$SCRIPT_DIR/env.sh" ]; then
    source "$SCRIPT_DIR/env.sh"
else
    echo "ERROR: env.sh not found. Run setup-toolchain.sh first!"
    exit 1
fi

echo "=========================================="
echo "  Arch R Build System"
echo "=========================================="
echo ""
echo "Device: $ARCHR_DEVICE"
echo "SoC: $ARCHR_SOC"
echo ""

# Parse arguments
BUILD_KERNEL=0
BUILD_ROOTFS=0
BUILD_IMAGE=0

if [ $# -eq 0 ]; then
    BUILD_KERNEL=1
    BUILD_ROOTFS=1
    BUILD_IMAGE=1
else
    for arg in "$@"; do
        case $arg in
            kernel)  BUILD_KERNEL=1 ;;
            rootfs)  BUILD_ROOTFS=1 ;;
            image)   BUILD_IMAGE=1 ;;
            all)
                BUILD_KERNEL=1
                BUILD_ROOTFS=1
                BUILD_IMAGE=1
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Usage: $0 [kernel|rootfs|image|all]"
                exit 1
                ;;
        esac
    done
fi

# Build steps
if [ $BUILD_KERNEL -eq 1 ]; then
    echo ""
    echo "=== Building Kernel ==="
    if [ -x "$SCRIPT_DIR/build-kernel.sh" ]; then
        "$SCRIPT_DIR/build-kernel.sh"
    else
        echo "WARNING: build-kernel.sh not found or not executable"
    fi
fi

if [ $BUILD_ROOTFS -eq 1 ]; then
    echo ""
    echo "=== Building Root Filesystem ==="
    if [ -x "$SCRIPT_DIR/build-rootfs.sh" ]; then
        "$SCRIPT_DIR/build-rootfs.sh"
    else
        echo "WARNING: build-rootfs.sh not found or not executable"
    fi
fi

if [ $BUILD_IMAGE -eq 1 ]; then
    echo ""
    echo "=== Building SD Card Image ==="
    if [ -x "$SCRIPT_DIR/build-image.sh" ]; then
        "$SCRIPT_DIR/build-image.sh"
    else
        echo "WARNING: build-image.sh not found or not executable"
    fi
fi

echo ""
echo "=========================================="
echo "  Build Complete!"
echo "=========================================="
echo ""
echo "Output files are in: $ARCHR_OUTPUT"
ls -la "$ARCHR_OUTPUT" 2>/dev/null || echo "(empty)"
