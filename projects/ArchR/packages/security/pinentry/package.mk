# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ArchR

PKG_NAME="pinentry"
PKG_VERSION="1.3.2"
PKG_SHA256="8e986ed88561b4da6e9efe0c54fa4ca8923035c99264df0b0464497c5fb94e9e"
PKG_LICENSE="GPL"
PKG_SITE="https://gnupg.org/"
PKG_URL="https://gnupg.org/ftp/gcrypt/pinentry/pinentry-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain libgpg-error libassuan"
PKG_LONGDESC="Passphrase entry helpers used by GnuPG 2.x. ArchR ships only the
TTY/curses variants; the GUI ones (gnome3, qt5, gtk2, fltk) would pull
desktop dependencies that the handheld doesn't have."

PKG_CONFIGURE_OPTS_TARGET="--enable-pinentry-tty \
                           --enable-pinentry-curses \
                           --disable-pinentry-emacs \
                           --disable-pinentry-gnome3 \
                           --disable-pinentry-gtk2 \
                           --disable-pinentry-qt \
                           --disable-pinentry-qt5 \
                           --disable-pinentry-fltk \
                           --disable-rpath \
                           --without-libcap \
                           --without-libsecret"
