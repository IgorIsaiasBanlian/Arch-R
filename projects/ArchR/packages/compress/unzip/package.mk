# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="unzip"
PKG_VERSION="6.0"
PKG_SHA256="036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37"
PKG_LICENSE="Info-ZIP"
PKG_SITE="https://infozip.sourceforge.net/UnZip.html"
PKG_URL="https://downloads.sourceforge.net/infozip/unzip60.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Info-ZIP unzip utility for extracting ZIP archives."
PKG_TOOLCHAIN="make"

make_target() {
  make -f unix/Makefile generic CC="${CC}" LD="${CC}" CF="${CFLAGS} -DUNIX -I." LF2="${LDFLAGS}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -a unzip ${INSTALL}/usr/bin/
}
