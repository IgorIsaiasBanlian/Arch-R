# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="compat-libjpeg62"
PKG_VERSION="3.0.1"
PKG_SHA256="5b9bbca2b2a87c6632c821799438d358e27004ab528abf798533c15d50b39f82"
PKG_LICENSE="BSD"
PKG_SITE="https://libjpeg-turbo.org/"
PKG_URL="https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libjpeg-turbo 3.0.1 built with the classic IJG v6b ABI (libjpeg.so.62) for the PortMaster compat layer. ArchR's base libjpeg-turbo ships the jpeg8 ABI (libjpeg.so.8); ports compiled against standard libjpeg-turbo expect libjpeg.so.62 (PortMaster_CFW.md section 4, 'commonly expected'). Installed to /usr/lib/compat and exposed in the default path by archr-compat-symlinks."
PKG_TOOLCHAIN="cmake"
PKG_BUILD_FLAGS="+pic"

# Default WITH_JPEG8=OFF yields the SONAME libjpeg.so.62 (vs the base
# package's WITH_JPEG8=ON which yields libjpeg.so.8). TurboJPEG and the
# CLI tools are not needed for the compat shim.
PKG_CMAKE_OPTS_TARGET="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
                       -DENABLE_STATIC=OFF \
                       -DENABLE_SHARED=ON \
                       -DWITH_JPEG8=OFF \
                       -DWITH_TURBOJPEG=OFF"

if target_has_feature "(neon|sse)"; then
  PKG_CMAKE_OPTS_TARGET+=" -DWITH_SIMD=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DWITH_SIMD=OFF"
fi

post_makeinstall_target() {
  # Keep only the versioned libjpeg.so.62 in the compat layer; the base
  # libjpeg-turbo owns /usr/lib/libjpeg.so.8, so we must not leave any
  # libjpeg in /usr/lib that would collide at image-merge time.
  mkdir -p ${INSTALL}/usr/lib/compat
  if compgen -G "${INSTALL}/usr/lib/libjpeg.so.62*" > /dev/null; then
    cp -a ${INSTALL}/usr/lib/libjpeg.so.62* ${INSTALL}/usr/lib/compat/
  fi

  rm -rf ${INSTALL}/usr/include
  rm -rf ${INSTALL}/usr/bin
  rm -rf ${INSTALL}/usr/share
  rm -rf ${INSTALL}/usr/lib/pkgconfig
  rm -rf ${INSTALL}/usr/lib/cmake
  rm -f  ${INSTALL}/usr/lib/libjpeg.so*
  rm -f  ${INSTALL}/usr/lib/libturbojpeg.so*
}
