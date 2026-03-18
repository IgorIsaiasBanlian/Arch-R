# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/sysutils/e2fsprogs/package.mk

PKG_CONFIGURE_OPTS_HOST="${PKG_CONFIGURE_OPTS_HOST} \
                         --disable-libblkid \
                         --disable-libuuid"
