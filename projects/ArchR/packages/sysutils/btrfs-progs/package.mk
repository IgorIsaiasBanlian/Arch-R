# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/addons/tools/btrfs-progs/package.mk

PKG_ARCH="aarch64"
PKG_CONFIGURE_OPTS_TARGET+=" --disable-zstd"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/sbin
    cp -P ${PKG_BUILD}/{btrfs,btrfsck,btrfstune,fsck.btrfs,mkfs.btrfs} ${INSTALL}/usr/sbin
}
