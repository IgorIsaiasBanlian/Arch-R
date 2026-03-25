# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026 ArchR (standalone - original sourced from packages/addons/)

PKG_NAME="btrfs-progs"
PKG_VERSION="6.14"
PKG_SHA256="5a85b791f0f32a4994e864ac4cb7abccce08e56db3010a1855ad0edeebc70b4c"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL"
PKG_SITE="https://btrfs.readthedocs.io/"
PKG_URL="https://github.com/kdave/btrfs-progs/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain util-linux zlib systemd lzo"
PKG_LONGDESC="Tools for the btrfs filesystem"
PKG_TOOLCHAIN="configure"

PKG_CONFIGURE_OPTS_TARGET="--disable-backtrace \
                           --disable-convert \
                           --disable-documentation \
                           --disable-python \
                           --disable-zstd"

pre_configure_target() {
  ./autogen.sh
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/sbin
    cp -P ${PKG_BUILD}/{btrfs,btrfsck,btrfstune,fsck.btrfs,mkfs.btrfs} ${INSTALL}/usr/sbin
}
