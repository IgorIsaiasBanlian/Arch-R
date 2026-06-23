# FHS migration plan: `/storage` -> Arch layout

Documento operacional para a Fase 2.2 da Arch-ificação. Acompanha cada fase do trabalho, registra decisões, lista checkpoints de validação. Não deletar enquanto a migração não estiver 100% concluída.

## Princípios não-negociáveis

1. **Nenhuma fase pode quebrar a release anterior.** Toda mudança que move dados precisa de migration script no boot que faz `mv` ou `cp -a` + symlink de fallback, idempotente, com fail-open (se algo der errado, mantém o path antigo).
2. **Verificação por grep depois de cada arquivo alterado.** Não emendar mudanças sem ter rodado `grep -rn '/storage/<x>' projects/ packages/` e confirmado que sumiu.
3. **Variáveis primeiro, dados depois.** A vazão Arch é: introduzir `${ARCHR_X}`, fazer apontar para `/storage/<x>`, migrar scripts para usar a variável, **só depois** mudar a variável para apontar para o destino FHS.
4. **Saves e ROMs por último.** Esses são dados que o usuário não pode perder. Última fase, migration script extensivamente testado.
5. **Symlinks de compat ficam por uma release.** Removidos só na release seguinte, depois de feedback do canal `stable`.

## Classes de destino

Classificação automática dos 297 paths únicos (auditados em 2026-06-23 contra `projects/ArchR/` + `packages/`):

| Classe | Conteúdo | Destino FHS | Variável | Refs únicas |
|--------|----------|-------------|----------|-------------|
| **A** | Config de sistema (hosts, modprobe, pulse, profile.d, modules-load) | `/etc/archr/<x>` ou `/etc/<x>` | `ARCHR_ETC=/etc/archr` | 18 |
| **B** | Config de app/emulador (drastic, dolphin, ppsspp, retroarch, ES) | `${XDG_CONFIG_HOME:-/var/lib/archr/config}/<app>` | `ARCHR_CONFIG=/var/lib/archr/config` | 76 |
| **C** | Cache regenerável (mesa_shader_cache, fontconfig, journal, services state) | `/var/cache/archr/<x>` | `ARCHR_CACHE=/var/cache/archr` | 44 |
| **D** | State/data persistente (.local/share, pacman db, kodi, joypads, overlays) | `/var/lib/archr/<x>` ou padrão da app | `ARCHR_DATA=/var/lib/archr/data` | 37 |
| **E** | Dados do usuário (roms, saves, screenshots, recordings, downloads, music, .ssh) | `/var/lib/archr/games` e amigos | `ARCHR_GAMES=/var/lib/archr/games` | 70 |
| **F** | Logs | `/var/log/archr/<x>` | já é padrão FHS | 4 |
| **G** | Temp (.tmp, .update, .boot.hint) | `/var/tmp/archr` | `ARCHR_TMP=/var/tmp/archr` | 9 |
| **Z** | Casos especiais (assets, jdk, nfs-mount, .opt, .hatari, .emulationstation, openbor) | caso a caso | individual | ~10 |

### Por que `/var/lib/archr` e não `/home/<user>`?

ArchR roda single-user como root no boot (modelo handheld + LibreELEC). Não tem `useradd` no provisioning. `$HOME` aponta para `/root` no console, mas a maioria dos serviços do EmulationStation já roda como root também. Mover para `/home/<user>` exigiria reescrever o modelo de usuário, e isso é fora do escopo da 2.2 (vira tarefa nova quando/se for adotada).

`/var/lib/archr/<x>` mantém o single-user model existente e é onde FHS recomenda colocar "state information of programs". Quando/se um modelo multi-user for adotado, é só mudar `ARCHR_DATA` para `/home/$USER/.local/share`.

### Por que `/var/cache/archr`?

`/var/cache/<programa>` é convenção FHS, mas como ArchR tem ~30 caches diferentes (services, mesa_shader_cache, fontconfig etc.), agrupar sob `/var/cache/archr/<x>` evita poluir `/var/cache` com 30 dirs nossos. Caches "famosos" (fontconfig, mesa) ficam onde a app espera (`/var/cache/fontconfig`, `$MESA_SHADER_CACHE_DIR`).

## Plano por fases

Cada fase **termina em um commit** com mensagem `FHS Fx.y: <descrição>`. Entre fases, validação obrigatória.

### Fase 0 — Infraestrutura de variáveis (NESTE PR)

**Objetivo:** introduzir vocabulário sem mover nada. Tudo continua em `/storage`.

- [ ] Criar `/etc/profile.d/archr-fhs.sh` exportando as 7 vars, todas apontando para `/storage/...` (compat).
- [ ] Documentar variáveis em `archr(7)` man page (já existe; adicionar seção `ENVIRONMENT`).
- [ ] Adicionar fallback `${ARCHR_CONFIG:-/storage/.config}` em scripts pra detectar quando estiverem migrados.

**Verificação:** `source /etc/profile.d/archr-fhs.sh && echo $ARCHR_CONFIG` retorna `/storage/.config` no momento.

**Risco:** zero. Nada muda no comportamento.

### Fase 1 — Class A: configs de sistema (no-op por design)

**Status: concluída como no-op (2026-06-23).** Auditoria detalhada revelou que `projects/ArchR/packages/sysutils/systemd/package.mk` **já redireciona** os paths Class A para `/etc/...` via symlinks de build-time:

```
ln -sf /storage/.config/modules-load.d ${INSTALL}/etc/modules-load.d
ln -sf /storage/.config/logind.conf.d ${INSTALL}/etc/systemd/logind.conf.d
ln -sf /storage/.config/resolved.conf.d ${INSTALL}/etc/systemd/resolved.conf.d
ln -sf /storage/.config/sleep.conf.d ${INSTALL}/etc/systemd/sleep.conf.d
ln -sf /storage/.config/timesyncd.conf.d ${INSTALL}/etc/systemd/timesyncd.conf.d
ln -sf /storage/.config/sysctl.d ${INSTALL}/etc/sysctl.d
ln -sf /storage/.config/tmpfiles.d ${INSTALL}/etc/tmpfiles.d
ln -sf /storage/.config/hwdb.d ${INSTALL}/etc/udev/hwdb.d
ln -sf /storage/.config/udev.rules.d ${INSTALL}/etc/udev/rules.d
```

No sistema rodando, `/etc/modules-load.d`, `/etc/sysctl.d`, `/etc/systemd/logind.conf.d` etc. **existem e funcionam como FHS espera**. O fato do target do symlink ser `/storage/.config` é detalhe interno do storage overlay (rootfs squashfs read-only + `/storage` rw), não dívida FHS visível ao usuário ou a ferramentas externas.

Mudar o target para algo mais Arch-friendly (ex.: `/var/lib/archr/etc/`) seria cosmético em troca de mexer no init para fazer bind-mount; o trade-off não compensa.

Hosts/resolv têm pipeline próprio (script `network-base-setup` lê
`/storage/.config/hosts.conf` e renderiza `/run/archr/hosts`); ficam onde estão pela mesma lógica.

**Resultado:** os 18 paths Class A já entregam FHS-correto sem mudança nenhuma. Foco da Fase 1 redirecionado para validação posterior em Fase 7 (auditoria final).

### Fase 2 — Class C: cache regenerável

**Status: concluída (2026-06-23).** A classificação automática inicial colocou 44 paths em Class C, mas a inspeção revelou que a maioria é **state** (ssh, wireguard, bluetooth, iwd, services, cron, samba auth, tailscale), **logs** (log/journal, log/runemu-debug.log) ou já está redirecionada via symlink no upstream. Os paths que de fato são "cache regenerável" foram quatro:

| Path | Destino FHS | Commit |
|------|-------------|--------|
| `/storage/.cache/mesa_shader_cache` | `/var/cache/mesa` | F2.1 |
| `/storage/.cache/fontconfig` | `/var/cache/fontconfig` | F2.2 |
| `/storage/.cache/kernel-overlays` | `/var/cache/archr/kernel-overlays` | F2.3 |
| `/storage/.cache/locpath` | `/var/cache/archr/locpath` | F2.3 |
| `/storage/.cache/fstrim.run` | `/var/cache/archr/fstrim.run` | F2.4 |

**Padrão de implementação:** bridge symlink instalado pelo `archr` meta-package (`/var/cache/<x>` ou `/var/cache/archr/<x>` → `/storage/.cache/<x>`). Consumers leem do path Arch-friendly; writes atravessam pro overlay rw. Mesmo padrão dos symlinks que o systemd já cria para `/etc/*`.

**Já no-op (redirected por outros pacotes upstream):**
- `/storage/.cache/journald.conf.d` (symlink criado pelo systemd package)
- `/storage/.cache/systemd-machine-id` (symlink criado pelo busybox package)
- `/storage/.cache/system_timezone` (symlink criado pelo emulationstation package)

**Realocados para outras fases:**
- `log/`, `log/journal`, `log/runemu-debug.log`, `logfiles` → **Fase 3** (Class F)
- `ssh`, `wireguard`, `samba`, `bluetooth`, `iwd`, `tailscale`, `connman`, `rfkill`, `services`, `cron`, `cores` → **Fase 4** (Class D, state)
- `timezone` → **Fase 7** (referenciado em patch do systemd; mover requer ajuste no patch)
- `debug.archr` → **Fase 7** (stamp file trivial)

### Fase 3 — Class F + G: logs e temp

**Status: concluída (2026-06-23).** Logs viram `/var/log/*` (que já é mount unit redirecionando para `/storage/.cache/log`); update vira `/var/cache/archr/update` via bridge symlink; overlayfs workdirs e bootloader handshake ficam no backing path por constraint de arquitetura.

| Path | Destino | Mecanismo |
|------|---------|-----------|
| `/storage/.cache/log/journal` | `/var/log/journal` | `var-log.mount` já existente (no-op) |
| `/storage/.cache/log/runemu-debug.log` | `/var/log/runemu-debug.log` | runemu.sh aponta direto pro `/var/log` (mount entrega) |
| `/storage/logfiles` | `/var/log/archr/archive` | createlog escreve via mount; tmpfiles cria backing |
| `/storage/.update` | `/var/cache/archr/update` | bridge symlink; consumers userland atualizados |

**Permanecem no backing path por design:**

- `/storage/.tmp/*-workdir` (assets, cores, database, games, joypads, overlays, shaders): são *workdirs* de `overlayfs` montados em `system.d/tmp-*.mount` units. O kernel exige que `upperdir` e `workdir` estejam no mesmo filesystem; como `upperdir=/storage/<x>`, o `workdir` tem que ficar no mesmo `/storage`. Mover para `/var/tmp/archr` quebraria os 6 mount units de assets/cores/database/joypads/overlays/shaders do RetroArch. No-op.
- `/storage/.boot.hint`: arquivo de handshake entre o bootloader U-Boot e o sistema rodando, gravado pré-boot pelo bootloader e lido por `autostart/003-upgrade`. Compartilhar via FHS exigiria mexer no script u-boot, fora de escopo. No-op.

**Pré-boot keep-as-is:**
- `busybox/scripts/init` (initramfs UPDATE_ROOT)
- `devices/RK3326/bootloader/update.sh` (escreve `.boot.hint`)
- `tmpfiles z_01_busybox.conf` (cria backing dirs)

Userland tudo usa o path Arch-friendly.

### Fase 4 — Class D: state/data persistente (37 paths)

**Objetivo:** mover state runtime sem perder histórico.

- `/storage/.pacman/db` → `/var/lib/pacman/db` (já é convenção pacman; ver Seção 2.1)
- `/storage/.pacman/cache` → `/var/cache/pacman/pkg`
- `/storage/.kodi` → `/var/lib/kodi`
- `/storage/.local/share/<x>` → `/var/lib/archr/data/<x>`
- `/storage/joypads`, `/storage/overlays`, `/storage/remappings`, `/storage/shaders` → `/var/lib/archr/<x>`

### Fase 5 — Class B: configs de app/emulador (76 paths)

**Objetivo:** maior parte do trabalho. Cada emulador é uma sub-fase.

Sub-fases sugeridas (ordem por isolamento):
1. EmulationStation (`/storage/.emulationstation`, `/storage/.config/emulationstation`)
2. RetroArch (`/storage/.config/retroarch`)
3. Standalone emulators, um por commit (drastic, dolphin, ppsspp, duckstation, melonDS, flycast, mednafen, mupen64plus, DaedalusX64, nanoboyadvance, hatari, gmu, gzdoom, idtech, vita3k, amiberry)
4. PortMaster (`/storage/.config/PortMaster`)
5. Utility apps (gptokeyb, foot, qterminal, box64, box86)

**Migration script extra-cuidadoso aqui.** Cada emulador tem saves e gamelist que o usuário criou. Operações:
- `cp -a /storage/.config/<emu> /var/lib/archr/config/<emu>` (não `mv` — fail-safe)
- Validar com `diff -r` que tudo foi copiado
- Symlink `/storage/.config/<emu>` -> destino
- Manter por uma release como fallback

### Fase 6 — Class E: dados do usuário (70 paths)

**Objetivo:** mover ROMs, saves, screenshots, recordings. **Fase de maior risco.**

- `/storage/roms` → `/var/lib/archr/games` (rom library)
- `/storage/screenshots` → `/var/lib/archr/games/screenshots`
- `/storage/recordings` → `/var/lib/archr/games/recordings`
- `/storage/downloads` → `/var/lib/archr/downloads`
- `/storage/music`, `/storage/pictures`, `/storage/videos`, `/storage/tvshows` → `/var/lib/archr/media/<x>`
- `/storage/.ssh` → `/root/.ssh` (FHS-correto pra root)
- `/storage/backup` → `/var/lib/archr/backup`

**Pré-requisitos antes desta fase:**
1. Todas as fases anteriores em produção há pelo menos uma release.
2. Migration script tem validação por checksum de cada arquivo migrado.
3. Fallback de rollback documentado.
4. Aviso ao usuário no upgrade ("vai mover ROMs, tempo estimado X").

### Fase 7 — Class Z: casos especiais e limpeza final

- `/storage/.emulationstation/es_input.cfg` → consolidar com Class B
- `/storage/jdk` → `/opt/jdk` (FHS standard pra third-party)
- `/storage/.opt` → `/opt/archr-local`
- `/storage/.nfs-mount` → `/mnt/nfs`
- `/storage/openbor` → `/var/lib/archr/games/openbor`
- `/storage/psvita/vita3k/ux0/app` → `${ARCHR_CONFIG}/vita3k/ux0/app`
- Remover symlinks de compat de fases anteriores.
- Auditoria final: `grep -rn '/storage/' projects/ packages/ scripts/` deve retornar zero matches em código (só docs/comentários).

## Checkpoints de validação por fase

Antes de cada commit fechar a fase:

1. `grep -rn '/storage/<path-migrado>' projects/ArchR/ packages/ scripts/` retorna zero matches em código.
2. `make docker-RK3326` compila sem erro novo.
3. Boot test em qemu/raspberry pi ou device real: systemd chega em `archr.target`, EmulationStation aparece, um emulador roda.
4. Diff de filesystem entre release anterior e nova: ver onde os dados realmente foram parar.
5. Migration script é idempotente (rodar 3x não deve corromper).

## Resgate em caso de regressão

Cada fase introduz um commit no `post-update` que faz a migração. Se for preciso reverter:

1. `git revert <commit-da-fase>` na branch.
2. Rebuild + nova release.
3. No próximo boot, `post-update` detecta que os paths antigos voltaram e cria symlinks reversos (estado intermediário).

Migration scripts ficam em `projects/ArchR/packages/archr/sources/post-update.d/fhs/Fx-<class>.sh`, ordenados.

## Estado atual

- [x] Auditoria de 297 paths concluída (2026-06-23).
- [x] Mapeamento por classe definido.
- [x] Fase 0 concluída (2026-06-23): `010-archr-fhs` em `/etc/profile.d`, archr(7) com seção ENVIRONMENT, vars apontando para `/storage/...`. Risco zero.
- [x] Fase 1 marcada como no-op (2026-06-23): systemd já entrega `/etc/{modules-load.d,sysctl.d,tmpfiles.d,udev/{hwdb,rules}.d,systemd/*conf.d}` via symlinks de build-time. FHS-correto sem mudança. Detalhes na seção da Fase 1 deste documento.
- [x] Fase 2 concluída (2026-06-23): 5 caches realmente regeneráveis migrados via bridge symlinks (mesa, fontconfig, kernel-overlays, locpath, fstrim.run). Paths state/log realocados para F3/F4. Detalhes na Fase 2.
- [x] Fase 3 concluída (2026-06-23): logs reaproveitam `var-log.mount` (/var/log = /storage/.cache/log), update bridged via `/var/cache/archr/update`, overlayfs workdirs e bootloader handshake permanecem no backing path por constraint.
- [ ] Fase 4..7 — não iniciadas.
