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

### Fase 1 — Class A: configs de sistema (18 paths)

**Objetivo:** mover configs que são `/etc` por natureza, não estado de usuário.

Paths-alvo (subset, completar após varredura):
- `/storage/.config/hosts.conf` → `/etc/archr/hosts.conf`
- `/storage/.config/modprobe.d/` → `/etc/modprobe.d/`
- `/storage/.config/modules-load.d/` → `/etc/modules-load.d/`
- `/storage/.config/hwdb.d/` → `/etc/udev/hwdb.d/`
- `/storage/.config/profile.d/` → `/etc/profile.d/`
- `/storage/.config/logind.conf.d/` → `/etc/systemd/logind.conf.d/`
- `/storage/.config/pulse-daemon.conf.d/` → `/etc/pulse/daemon.conf.d/`
- `/storage/.config/iproute2/` → `/etc/iproute2/`

**Implementação:** um path por commit. Migration script no `post-update` faz `mv` + symlink de fallback (`/storage/.config/hosts.conf` -> `/etc/archr/hosts.conf`).

**Verificação:** grep + boot test em qemu antes de avançar (kernel boot, systemd inicia, EmulationStation aparece).

### Fase 2 — Class C: cache (44 paths)

**Objetivo:** mover caches regeneráveis. Se algo der errado, perde-se ms de regeneração, não dados.

- `/storage/.cache/mesa_shader_cache` → `/var/cache/mesa` (já é convenção)
- `/storage/.cache/fontconfig` → `/var/cache/fontconfig`
- `/storage/.cache/services` → `/var/cache/archr/services`
- `/storage/.cache/cores` → `/var/cache/archr/cores`
- `/storage/.cache/kernel-overlays` → `/var/cache/archr/kernel-overlays`
- demais → `/var/cache/archr/<x>`

**Verificação:** após boot, scraper + lançamento de jogo + replay do shader cache funcionando.

### Fase 3 — Class F + G: logs e temp (13 paths)

**Objetivo:** alinhar com convenção `/var/log` e `/var/tmp`.

- `/storage/.cache/log/journal` → `/var/log/journal` (já é convenção systemd)
- `/storage/.cache/log/runemu-debug.log` → `/var/log/archr/runemu-debug.log`
- `/storage/logfiles/` → `/var/log/archr/`
- `/storage/.tmp/*-workdir` → `/var/tmp/archr/*-workdir`
- `/storage/.update/` → `/var/cache/archr/update/`

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
- [ ] Fase 1 — não iniciada.
- [ ] Fase 2..7 — não iniciadas.
