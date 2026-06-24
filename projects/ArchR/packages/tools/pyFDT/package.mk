# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="pyFDT"
PKG_VERSION="0.3.3"
PKG_SHA256="f70b1008ea78a2a46429d2f3b06a2a71f2bfd59a5e13000c2f3f2a957b57ea9b"
PKG_LICENSE="Apache-2.0"
PKG_SITE="https://github.com/molejar/${PKG_NAME}"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.zip"
PKG_DEPENDS_TARGET="Python3"
PKG_LONGDESC="This python module is usable for manipulation with Device Tree Data and primary was created for imxsb tool"
PKG_TOOLCHAIN="manual"

pre_configure_target() {
  cd ${PKG_BUILD}
  rm -rf .${TARGET_NAME}
}

make_target() {
  python3 setup.py build
}

makeinstall_target() {
  python3 setup.py install --root=${INSTALL} --prefix=/usr
}

post_makeinstall_target() {
  # setuptools writes the build-host python3 path into entry-point
  # shebangs, which then point at /media/.../toolchain/bin/python3 on
  # the target and refuse to run. Rewrite to /usr/bin/python3 (the
  # target's interpreter).
  for s in ${INSTALL}/usr/bin/pydtc; do
    [ -f "$s" ] || continue
    sed -i '1s|^#!.*python.*|#!/usr/bin/python3|' "$s"
  done
}
