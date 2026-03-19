# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="AIC8800"
PKG_VERSION="1018f17a629c638acc1a01df19e3f2146e7b4f5c"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/friddle/arch-aic8800-6.12"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="AICsemi AIC8800 USB WiFi+BT driver and firmware"
PKG_TOOLCHAIN="make"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS

  # Switch platform from Ubuntu to manual cross-compilation
  sed -i 's/CONFIG_PLATFORM_UBUNTU ?= y/CONFIG_PLATFORM_UBUNTU ?= n/' \
    ${PKG_BUILD}/drivers/aic8800/Makefile
}

make_target() {
  make V=1 \
       ARCH=${TARGET_KERNEL_ARCH} \
       KDIR=$(kernel_path) \
       CROSS_COMPILE=${TARGET_KERNEL_PREFIX} \
       -C ${PKG_BUILD}/drivers/aic8800
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/
    find ${PKG_BUILD}/drivers/aic8800 -name "*.ko" \
      -exec cp {} ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/ \;

  # Install firmware
  mkdir -p ${INSTALL}/usr/lib/firmware/aic8800DC
    cp -r ${PKG_BUILD}/fw/aic8800DC/* ${INSTALL}/usr/lib/firmware/aic8800DC/

  # Install udev rules for AIC8800 USB mode switching
  mkdir -p ${INSTALL}/usr/lib/udev/rules.d
    cp ${PKG_BUILD}/aic.rules ${INSTALL}/usr/lib/udev/rules.d/99-aic8800.rules
}
