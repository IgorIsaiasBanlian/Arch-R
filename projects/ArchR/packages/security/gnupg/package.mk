# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ArchR

PKG_NAME="gnupg"
PKG_VERSION="2.4.8"
PKG_SHA256="b58c80d79b04d3243ff49c1c3fc6b5f83138eb3784689563bcdd060595318616"
PKG_LICENSE="GPL"
PKG_SITE="https://gnupg.org/"
PKG_URL="${PKG_SITE}ftp/gcrypt/gnupg/gnupg-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain zlib bzip2 libgpg-error libgcrypt libassuan \
                    libksba npth pinentry"
PKG_LONGDESC="The GNU Privacy Guard 2.x: OpenPGP and S/MIME implementation."

# Pacman 7.x calls into gpg with --check-signatures and Ed25519 keys; both
# are 2.x-only features that the LibreELEC-era 1.4.x branch never grew.

PKG_CONFIGURE_OPTS_TARGET="--disable-rpath \
                           --disable-doc \
                           --disable-gpg-idea \
                           --disable-gpg-cast5 \
                           --disable-gpg-md5 \
                           --disable-gpg-rmd160 \
                           --disable-ldap \
                           --disable-photo-viewers \
                           --disable-card-support \
                           --disable-scdaemon \
                           --disable-dirmngr \
                           --disable-wks-tools \
                           --disable-tofu \
                           --disable-gnutls \
                           --with-pinentry-pgm=/usr/bin/pinentry-tty"

pre_configure_target() {
  # GnuPG 2.x's configure occasionally trips over -Werror on hosts with
  # newer GCCs.
  export CFLAGS="${CFLAGS} -Wno-error"
}
