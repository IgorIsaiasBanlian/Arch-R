# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="gpudriver"
PKG_VERSION=""
PKG_LICENSE="GPLv2"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET=""
PKG_TOOLCHAIN="manual"
PKG_LONGDESC="GPU driver util for switching between panfrost / panthor and libmali / libmali-vulkan"

post_makeinstall_target() {
  # Install OUTSIDE /usr/bin while the panfrost path is still unreliable
  # on RK3326 clones. EmulationStation surfaces the GPU DRIVER selector
  # only when `/usr/bin/gpudriver` exists (see es-app GuiMenu.cpp), so
  # placing it under /usr/lib/archr/ hides the picker without removing
  # any boot-time functionality — the autostart hook (003-gpudriver)
  # calls this binary by full path. Move back to /usr/bin/gpudriver
  # once panfrost on the Mali-G31 path stops hanging the kernel.
  mkdir -p "${INSTALL}/usr/lib/archr/"
  cp -v "${PKG_BUILD}/bin/gpudriver" "${INSTALL}/usr/lib/archr/"
  GPUDRIVER_BIN="${INSTALL}/usr/lib/archr/gpudriver"

  # set the correct mesa pan kernel driver module based on device
  case ${DEVICE} in
    RK3588)
      PAN="panthor"
      DTB_OVERLAY_LOAD="\/usr\/bin\/dtb_overlay set driver-gpu driver-gpu-panthor.dtbo"
      DTB_OVERLAY_UNLOAD="\/usr\/bin\/dtb_overlay set driver-gpu None"
    ;;
    S922X)
      PAN="panfrost"
      DTB_OVERLAY_LOAD="\/usr\/bin\/dtb_overlay set driver-gpu driver-gpu-panfrost.dtbo"
      DTB_OVERLAY_UNLOAD="\/usr\/bin\/dtb_overlay set driver-gpu None"
    ;;
    *)
      # No DTB overlay needed: kernel base DTS already has the GPU node
      # with 'arm,mali-bifrost' compatible, so panfrost binds directly
      # via modprobe. Switching between libmali and panfrost just
      # requires loading/unloading the kernel module and swapping the
      # userspace GL library binds.
      PAN="panfrost"
      DTB_OVERLAY_LOAD=""
      DTB_OVERLAY_UNLOAD=""
    ;;
  esac

  sed -e "s/@PAN@/${PAN}/g" \
      -i  "${GPUDRIVER_BIN}"

  sed -e "s/@DTB_OVERLAY_LOAD@/${DTB_OVERLAY_LOAD}/g" \
      -i  "${GPUDRIVER_BIN}"

  sed -e "s/@DTB_OVERLAY_UNLOAD@/${DTB_OVERLAY_UNLOAD}/g" \
      -i  "${GPUDRIVER_BIN}"
}