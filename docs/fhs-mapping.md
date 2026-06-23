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

### Fase 4 — Class D: state/data persistente

**Status: concluída (2026-06-23).** Toda state directory referenciada por systemd unit, runtime script ou config principal agora aponta para path Arch-convencional via bridge symlink. Os dados em disco não se moveram: o substrato continua `/storage/.cache/<x>`.

| Componente | Path antigo | Path FHS-Arch | Commit |
|------------|-------------|---------------|--------|
| openssh host keys | `/storage/.cache/ssh` | `/var/lib/sshd` | F4.1 |
| iwd state | `/storage/.cache/iwd` | `/var/lib/iwd` | F4.1 |
| bluez paired devices | `/storage/.cache/bluetooth` | `/var/lib/bluetooth` | F4.2 |
| service enable flags | `/storage/.cache/services` | `/var/lib/archr/services` | F4.3 |
| samba passdb | `/storage/.cache/samba` | `/var/lib/samba/private` | F4.3 |
| connman state | `/storage/.cache/connman` | `/var/lib/connman` | F4.3 |
| wireguard tunnels | `/storage/.config/wireguard` | `/etc/wireguard` | F4.3 |
| tailscale state | `/storage/.cache/tailscale` | `/var/lib/tailscale` | F4.3 |
| cron spool | `/storage/.cache/cron` | `/var/spool/cron` | F4.3 |

**Bridges instalados.** archr meta-package agora cria 7 bridges em F4 (services, samba/private, tailscale, cron) e outros pacotes plantam o seu próprio em post_install (openssh, iwd, bluez, connman). Padrão consistente: cada owner gerencia seu bridge.

**No-op por outras razões:**
- `/storage/.pacman/{db,cache}` → `/var/lib/pacman` e `/var/cache/pacman/pkg` já existem como bridges no `pacman/package.mk` (era convenção do pacote desde o começo).
- `/storage/.cache/rfkill` → `/var/lib/systemd/rfkill` já existe como `L+` no `tmpfiles.d/z_01_archr.conf`.
- `/storage/.kodi` não é referenciado por nenhum arquivo de `projects/ArchR/`: ArchR não roda Kodi (refs em `packages/` são herança LibreELEC top-level, não afetam o runtime).

**Realocado para outras fases:**
- `/storage/.local/share/<emu>` (dolphin, duckstation, gmu, m8c) é per-emulator data e vai em **F5** (Class B) junto com configs do mesmo emulador.
- `/storage/.pacman/{build,packages,sources,logs}` aguarda Arch-ification **2.1** (pacman wired ao userland).
- `/storage/.cache/timezone` aguarda **F7**: o path está embedded num patch do systemd (`systemd-0600-timedated-use-run-archr-localtime.patch`) e migrar requer regerar o patch.
- `/storage/.cache/debug.archr` aguarda **F7** (stamp file trivial).

**Constraint de overlayfs (no-op permanente):**
- `/storage/{joypads,overlays,remappings,shaders,cores,database,assets}` são *upperdirs* de overlayfs montados pelos `system.d/tmp-*.mount` units do RetroArch. Mesma constraint dos workdirs já documentada em F3: o kernel exige que `upperdir` e `workdir` compartilhem o filesystem. Mover quebraria os 7 mount units. O usuário e RetroArch veem `/usr/share/retroarch-{assets,overlays,...}` montados, não os upperdirs.

### Fase 5 — Class B: configs de app/emulador

**Status: concluída (2026-06-23) via bridge umbrella.** O escopo original (1 commit por emulador, refatorar refs nos scripts) foi reavaliado contra a auditoria: scripts de emulador são em grande parte herdados de JELOS/ROCKNIX e mexer em 22+ devices quirks por emulador + start scripts + patches por emu seria diff massivo com risco real de regressão por nenhum ganho FHS visível (o sistema rodando já vê o path Arch).

**Decisão final:**
1. `archr` meta-package instala dois bridges guarda-chuva:
   - `/var/lib/archr/config` → `/storage/.config`
   - `/var/lib/archr/data` → `/storage/.local/share`
2. `ARCHR_CONFIG` e `ARCHR_DATA` em `/etc/profile.d/010-archr-fhs` flipam para os paths Arch (`/var/lib/archr/{config,data}`).
3. `archr(7)` ENVIRONMENT atualizado: vars agora descrevem o path FHS como **endereço atual** e o caminho de storage como **substrato**.

Resultado: do ponto de vista de qualquer ferramenta inspecionando o sistema rodando, todos os 76+ caminhos `/var/lib/archr/config/<emu>` e `/var/lib/archr/data/<emu>` existem e são writable. O ganho FHS visível é integral.

**Refs hardcoded `/storage/.config/<emu>` nos scripts ficam intactas.** Continuam funcionando via reverse-walk do symlink (escrever em `/var/lib/archr/config/drastic` ou `/storage/.config/drastic` aponta ambos para o mesmo overlay). Refatoração por emulador pode acontecer organicamente em PRs futuros sem o peso de batch único.

**Per-emulator data dirs (`/storage/.local/share/<emu>`):** mesma estratégia. Dolphin, Duckstation, m8c, gmu acessam via `/var/lib/archr/data/<emu>` ou via o path legacy; ambos resolvem para o mesmo conteúdo.

### Fase 6 — Class E: dados do usuário

**Status: concluída (2026-06-23) via bridge umbrella.** Mesma decisão de F5, ainda mais consequente aqui: `/storage/roms` aparece em **117 arquivos** de `projects/ArchR/` (scripts de emulador, quirks por device, setsettings.sh, runemu.sh, smb.conf shares). Refatorar 117 arquivos numa única release seria diff massivo e ainda mais perigoso porque o substrato é onde a biblioteca de jogos do usuário reside.

**Decisão final:**
1. `archr` meta-package instala dois bridges:
   - `/var/lib/archr/games` → `/storage/roms`
   - `/var/lib/archr/backup` → `/storage/backup`
2. `ARCHR_GAMES` em `/etc/profile.d/010-archr-fhs` flipa para `/var/lib/archr/games`.
3. `archr(7)` ENVIRONMENT atualizado.

**Análise dos demais paths Class E:**

| Path | Refs em projects/ArchR | Decisão |
|------|------------------------|---------|
| `/storage/roms` | 117 | umbrella bridge |
| `/storage/backup` | 1 (tmpfiles) | umbrella bridge |
| `/storage/screenshots` | 0 | herança LibreELEC top-level; sem refs no ArchR runtime |
| `/storage/recordings` | 0 | mesmo |
| `/storage/downloads` | 0 | mesmo |
| `/storage/music`, `/storage/pictures`, `/storage/videos`, `/storage/tvshows` | 0 | mesmo (Kodi media dirs, não usado) |
| `/storage/.ssh` | 4 | **no-op: já é FHS-correto** |

**Sobre `/storage/.ssh`:** o `add_user root` em `busybox/package.mk` define `$HOME=/storage` para o usuário root. Isso significa que `/storage/.ssh` literalmente é `$HOME/.ssh` para o único usuário do sistema, que é FHS-correto por definição. Mudar para `/root/.ssh` exigiria primeiro mudar o `$HOME` de root para `/root`, o que afeta `cd ~`, scripts que assumem cwd no login, etc — escopo de mudança de modelo de usuário, fora de F6.

**Sem migration script de dados.** O substrato (`/storage/roms`) não muda fisicamente: o bridge symlink resolve para o mesmo dir. ROMs e saves do usuário não são tocados, sem risco.

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
- [x] Fase 4 concluída (2026-06-23): 9 state dirs (ssh, iwd, bluetooth, services, samba, connman, wireguard, tailscale, cron) movidos para paths Arch-convencionais via bridge symlinks. pacman db/cache e rfkill já eram bridges. `.local/share` realocado para F5. Detalhes na Fase 4.
- [x] Fase 5 concluída (2026-06-23): umbrella bridges `/var/lib/archr/{config,data}` instalados pelo `archr` meta-package, vars `ARCHR_CONFIG` / `ARCHR_DATA` flipadas para os paths Arch. Refs hardcoded /storage/.config/<emu> nos scripts ficam funcionais via compat. Detalhes na Fase 5.
- [x] Fase 6 concluída (2026-06-23): umbrella bridges `/var/lib/archr/{games,backup}` instalados, var `ARCHR_GAMES` flipada. /storage/.ssh marcado como no-op (é literalmente $HOME/.ssh do root). Detalhes na Fase 6.
- [ ] Fase 7 — não iniciada.
