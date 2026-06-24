# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/virtual/debug/package.mk

PKG_DEPENDS_TARGET+=" nvtop apitrace valgrind vim"

# strace 6.19 quebra apenas em devices SM8650|SM8550|SM8250|H700 (case do
# packages/debug/strace/package.mk). Demais devices, incluindo RK3326,
# recebem strace 6.17 e funcionam normalmente.
case "${DEVICE}" in
  SM8650|SM8550|SM8250|H700)
    PKG_DEPENDS_TARGET=${PKG_DEPENDS_TARGET//"strace"/}
    ;;
esac

# ltrace (PortMaster_CFW.md section 10 nice-to-have) NAO foi adicionado:
# o upstream 0.7.3 (2013) esta abandonado e o fork mantido
# (gitlab.com/cespedes/ltrace) foi build-testado no toolchain do ArchR
# em 2026-06 e falha no autoreconf (configure.ac referencia config/m4
# inexistente no checkout; aclocal aborta). Sem suporte estavel a
# aarch64 + glibc moderna. Ports que precisem de tracing de symbol-level
# devem usar gdb (presente) ou perf trace (perf presente). Este e o unico
# item nice-to-have do guia intencionalmente ausente.
