# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ArchR (https://github.com/archr-linux)

PKG_NAME="archr-keyring"
PKG_VERSION="20260623"
PKG_LICENSE="GPL"
PKG_SITE="https://arch-r.io"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain gnupg"
PKG_LONGDESC="ArchR pacman keyring: master + signer public keys for package verification."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/pacman/keyrings

  # ArchR master + signer keys. When a real keyring is generated, ship:
  #   keys/archr.gpg          - public keyring file
  #   keys/archr-trusted      - trusted key fingerprints, one per line,
  #                             format: <fingerprint>:<trust-level>:<owner>
  #   keys/archr-revoked      - revoked fingerprints, one per line
  # The placeholder release ships an empty keyring; pacman runs with
  # SigLevel = Required DatabaseOptional and accepts unsigned packages
  # from the archr repo because the .db remains optional. Tighten to
  # 'Required' once the real master key is generated and signs the .db.
  for f in archr.gpg archr-trusted archr-revoked; do
    if [ -f "${PKG_DIR}/keys/${f}" ]; then
      cp "${PKG_DIR}/keys/${f}" ${INSTALL}/usr/share/pacman/keyrings/
    else
      : >${INSTALL}/usr/share/pacman/keyrings/${f}
    fi
  done
}
