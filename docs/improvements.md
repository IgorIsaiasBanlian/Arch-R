# Melhorias e modernização

Documento vivo. Lista componentes do ArchR que se beneficiam de modernização incremental: qualidade de código, integração com hardware atual (RK3326 / Mali-G31), manutenibilidade. Reescritas do zero ficam fora deste documento; quando o veredito for "vale reescrever", abrir doc próprio em `docs/rewrite-<componente>.md`.

**Convenção de status:**
- `[ ]` não iniciado
- `[~]` em progresso
- `[x]` concluído
- `[?]` investigação aberta, decisão pendente

**Convenção de esforço:** S (horas), M (dias), L (semanas), XL (mês ou mais).

---

## 1. EmulationStation (emulationstation-next)

**Repo:** `/media/disco-local/ArchR/emulationstation-next`
**Linguagem:** C++17, CMake 3.10+, SDL2.
**Hardware alvo primário:** R36S e clones (RK3326, Mali-G31, 1 GB DDR3L).

**Veredito de reescrita:** descartado em 2026-06-23 (sessão dga.teles + Claude). 15+ anos de trabalho cumulativo, ecossistema de temas, scraper, gamelist XML, integração PortMaster e RetroAchievements: o custo de paridade básica supera de longe o ganho. Modernização incremental é o caminho.

### 1.1. Qualidade de código

- [ ] **Auditoria de C++17 vs C++20** S. Já estamos em C++17 via CMake. Avaliar bump para C++20 (concepts, ranges, designated initializers, span) ou ficar no 17. Decisão depende do gcc do toolchain do ArchR.
- [ ] **Substituir loops manuais por algoritmos da STL** M. Varredura em `es-core/src/utils/` e `es-app/src/views/`, onde `for` com índice ainda predomina.
- [ ] **Smart pointers consistentes** M. Há mistura de `new`/`delete` cru com `unique_ptr`/`shared_ptr`. Padronizar e remover `delete` manual onde possível.
- [ ] **`constexpr` e `noexcept` em utilitários puros** S. Funções de path, parsing, math em `es-core/utils/`.
- [ ] **Análise estática regular** S. Rodar `clang-tidy` com perfil mínimo (`modernize-*`, `performance-*`, `readability-*`) e arquivar relatório em `docs/es-clang-tidy-<data>.txt`.
- [ ] **Remoção de código morto** S. O commit `563e1057f` (PackGamelists/BuildMultiDiskContentCache) sugere que ainda há referências obsoletas; varredura completa.

### 1.2. Compatibilidade RK3326 / Mali-G31

- [ ] **Paths de renderização Panfrost vs libmali** M. Quando o seletor de GPU driver voltar (atualmente oculto, ver `project_panfrost_selector_disabled`), o ES precisa dar caminhos de fallback diferentes para texture upload e shader cache. Hoje assume libmali.
- [ ] **BO labelling** S. Os patches `0007..0010` do kernel 6.12-LTS habilitam labels em BOs do panfrost. ES pode anotar suas texturas e ajudar `panfrost_gem_show` no debug. Baixa prioridade, mas é literalmente uma chamada IOCTL.
- [ ] **CMA 96 MB awareness** M. Pré-alocação de texture pool consciente do limite (R36S tem 96 MB de CMA reservado). Logar quando se aproxima do limite e degradar graciosamente em vez de OOM.
- [ ] **Shader cache persistente** M. Mesa 26.1.3 já tem `MESA_SHADER_CACHE_DIR`. Garantir que o ES aponte para `/storage/.cache/mesa` (não `/tmp`, que é tmpfs) e que a pasta sobreviva ao boot.
- [ ] **CPU governor durante navegação de menu** S. Hoje subimos governor para `performance` antes de lançar emulador. Avaliar manter `schedutil` durante navegação para reduzir consumo passivo e calor.

### 1.3. Performance percebida

- [ ] **Profiling de boot time** M. Medir `ExecMainStart` até primeira tela interativa. Identificar onde os ~5 a 8 segundos de boot do ES vão (XML parse, texture load, scraper init). O commit `a2181ff44` já paralelizou parte; rever o gap restante.
- [ ] **Async load de capas e screenshots** M. Verificar se o load atual já é não-bloqueante e se não, paralelizar via ThreadPool (já existe no repo, ver commit `268ebb394`).
- [ ] **Decoding incremental de imagens grandes** S. Sistemas com gamelists pesadas (capas a 2K) pagam decoding síncrono na entrada. Stream + downscale on-the-fly.
- [ ] **Transições de view** S. Frame pacing nas transições com Mali-G31 às vezes engasga; checar se há frame drop em transições de carousel.

### 1.4. Funcionalidades

- [ ] **GPU governor menu** S. Já implementado em `4c3cb8af3` e `b9cb6b821`. Validar UX e documentar opções.
- [ ] **Integração com overlay generator** M. Botão dentro do ES que abre `arch-r.io/overlay-generator/` ou rode local. Reduz fricção para clones não catalogados.
- [ ] **Integração com Flasher para atualizar painel** M. Quando o usuário troca o cartão de painel, oferecer dentro do ES "atualizar overlay" sem reflash da SD.
- [ ] **Modo party / split-screen UI** L. Discutido informalmente; especificar antes.
- [ ] **Indicador de modo de gravação MIPI/SPKO** S. Para boards Soysauce, mostrar qual variant de áudio está ativo (debug útil).

### 1.5. Build e dependências

- [ ] **CMake 3.10 → 3.20+** S. Bump do mínimo. Toolchain do ArchR já está bem além.
- [ ] **Substituir FetchContent por submodules ou pkg-config** S. Predição: builds reproduzíveis e cache friendly.
- [ ] **SDL2 → SDL3** XL. SDL3 estável em 2025/2026. Migração não é blocker, mas vale levantar custo. Investigação aberta.
- [ ] **CI no GitHub Actions** M. Build matrix (debug + release, gcc + clang) por PR; hoje só roda local.
- [ ] **clang-format obrigatório** S. Adicionar `.clang-format` no repo e rodar via pre-commit hook.

### 1.6. i18n e theming

- [ ] **Auditoria de strings hardcoded** S. Garantir que tudo passa por `_("...")` ou equivalente.
- [ ] **Suporte a novo formato de tema** L. Avaliar adoção do tema engine do batocera-emulationstation ou ES-DE para herdar ecossistema maior. Investigação aberta.

---

## 2. Arch-ificação da distro

**Objetivo estratégico:** mover ArchR progressivamente para a filosofia Arch Linux (rolling, pacman-centric, FHS rigoroso, KISS) e deixar de ser uma variação ROCKNIX/LibreELEC. Nenhuma mudança aqui pode quebrar a experiência atual; tudo é incremental, com fallback para o caminho LibreELEC enquanto a paridade não estiver garantida.

**Decisão arquitetural registrada (2026-06-23):** o modelo de boot herdado de LibreELEC (rootfs squashfs read-only + overlay `/storage` read-write + image-based atomic updates) **é decisão por design, não dívida técnica**. Não substituir. Motivos:
1. Sobrevive a power-loss arbitrário (criança puxando da tomada no meio do jogo), que é cenário diário em handheld.
2. Update atômico via swap de imagem é matematicamente impossível de deixar o sistema half-broken; pacman incremental, por design, pode.
3. `/storage` como overlay garante que upgrade de sistema nunca come saves nem configurações de emulador.
4. **Precedente validado:** SteamOS adotou exatamente esse modelo (rootfs read-only via OSTree, overlay `/home`, updates atômicos) e ainda assim é Arch Linux oficial com pacman e PKGBUILD plenamente funcionais. A arquitetura não define identidade de SO; userland, ferramentas e filosofia definem.

Identidade Arch vem dos 7 itens desta seção (pacman, PKGBUILD, FHS, rolling, KISS, ArchWiki, branding), não da forma como o boot acontece.

**Estado atual auditado (2026-06-23):**
- `pacman 7.0.0` já compilado em `projects/ArchR/packages/sysutils/pacman/` mas não está conectado ao fluxo de update do usuário final.
- `archr-keyring` já criado, populado com chaves Arch Linux ARM.
- `archr-update` ainda faz HTTP POST para `update.arch-r.io` e baixa imagem inteira (estilo LibreELEC overlay).
- 189 referências hardcoded a paths `/storage/...` em scripts (modelo overlay LibreELEC). FHS-puro seria `/etc`, `/var/lib`, `/home`.
- 809 arquivos com refs a `libreelec` (maioria headers de copyright; legítimo manter, ver 2.7).
- 8 arquivos com refs a `rocknix` em projects/ArchR: maioria é URL upstream ou crédito (legítimo); só 1 ou 2 são cosméticos.

### 2.1. Wirar pacman como mecanismo de update real

**Status: pipeline cliente pronto (2026-06-23).** Falta gerar a primeira release no `archr-linux/archr-repo` para o sistema ter o que sincronizar.

- [x] **Decisão de infra: GitHub Releases como mirror único.** Sem VPS, sem `repo.arch-r.io`. Detalhes em `docs/release-policy.md`. Google Drive como backup; Cloudflare R2 fica como fallback futuro se aparecer problema concreto.
- [x] **`archr-update` reescrito** como wrapper fino de `pacman -Syu`. 87 linhas (eram 188). Comandos: `archr-update [check|update|info]`. Channel lido de `system.cfg "updates.branch"` e refletido no mirrorlist via rewrite on-the-fly.
- [x] **`pacman.conf` apontando para o repo `archr`** (não mais Arch Linux ARM repos). `SigLevel = Required DatabaseOptional` durante bootstrap; aperta para `Required` quando o keyring de produção entrar.
- [x] **`pacman-init` adaptado**: testa conectividade via `github.com` em vez de `mirror.archlinuxarm.org`, popula keyring `archr` (não mais `archlinuxarm`).
- [x] **`archr-keyring` reformulado**: ship empty placeholders por enquanto, hooks prontos para receber o keyring real (`archr.gpg`, `archr-trusted`, `archr-revoked`) quando a chave master for gerada.
- [x] **`scripts/repo/gen-pacman-repo`**: empacota `build.*/install_pkg/<pkg>/` em `.pkg.tar.zst`, gera `.PKGINFO`, monta `archr.db` via `repo-add`. README ao lado documenta o workflow `gh release create repo-<canal>`.
- [ ] **Gerar a chave master GPG**: chave ArchR offline + subchave de signer. Atualizar `archr-keyring/keys/` com `archr.gpg`, `archr-trusted`, `archr-revoked`. Bloqueia o primeiro release assinado.
- [ ] **Primeira release no `archr-linux/archr-repo`**: criar o repo no GitHub, rodar `gen-pacman-repo` em build local, publicar `repo-dev` para teste interno antes de promover para `repo-next` e `repo-stable`.
- [ ] **CI no `archr-linux/Arch-R`** que invoque `gen-pacman-repo` após `make docker-RK3326` e publique no `archr-repo` automaticamente. GitHub Actions free tier basta.

### 2.2. Aproximar do FHS

- [x] **Auditoria das 297 paths únicos** completada (2026-06-23). Classificadas em A-G + Z, registradas em `docs/fhs-mapping.md`.
- [x] **22 bridge symlinks instalados** (17 no `archr` meta-package + 5 modulares em openssh, iwd, bluez, connman, fontconfig). Surface FHS-Arch, substrato continua em `/storage` rw overlay (mesmo padrão do SteamOS e dos symlinks que o systemd já fazia para `/etc/*`).
- [x] **Sete variáveis `ARCHR_*`** em `/etc/profile.d/010-archr-fhs` exportam os paths Arch (`ARCHR_CONFIG=/var/lib/archr/config`, `ARCHR_GAMES=/var/lib/archr/games`, etc.).
- [x] **archr(7) ENVIRONMENT** documenta cada variável e seu substrato.
- [x] Migração concluída em **7 fases** (F0..F7), todas commitadas em `new-arch`. Ver `docs/fhs-mapping.md`.
- [ ] **Refatoração orgânica das 1625 refs hardcoded `/storage/...`** que sobrevivem em scripts de emulador, quirks por device, automount, factoryreset, post-update. Não-bloqueante: continua tudo funcionando via compat. Vai virar PRs incrementais quando algum dos scripts for tocado por outro motivo.

### 2.3. Aceitar PKGBUILD da comunidade

- [ ] **Diretório `archr-aur/` num repo separado** L. Espelho do AUR do Arch, mas com PKGBUILDs validados em RK3326. Build local via `makepkg` + chroot.
- [ ] **`makepkg.conf` próprio com flags do RK3326** S. Cortex-A35 não tem NEON 2.0 nem SVE; o flag set padrão do Arch ARM precisa de ajuste. Já temos `makepkg.conf` no package.mk do pacman; revisar conteúdo.
- [ ] **CI que builda PRs de PKGBUILD** M. GitHub Actions roda `makepkg --check --noconfirm` em PR; só merge se passa.

### 2.4. Rolling release oficial

- [x] **Decidir e documentar política de release** S. Definido em `docs/release-policy.md`: semver-RC mantido até v2.0 final, snapshots mensais `YYYY.MM.PATCH` a partir de v2.0. Canais `stable`/`next`/`dev` mapeiam direto para a variável `updates.branch` que `archr-update` já entende.
- [ ] **Servidor `update.arch-r.io` interpretando `BRANCH=stable|next|dev`** M. Cliente já manda; falta o backend retornar build correto por canal.
- [ ] **Versionamento `YYYY.MM.PATCH` ativado pós-v2.0** S. Tag git `vYYYY.MM.PATCH`. Mexer só depois que a v2.0 final sair.
- [ ] **GitHub Releases com tags `[Action Required]` / `[Action Recommended]` / `[News]`** S. Convenção documentada em `release-policy.md`. Tooling consumidor (Flasher, archr-update) pode parsear depois.

### 2.5. KISS e remoção de inertia

- [x] **Poda de quirks de hardware mortas** (2026-06-23). 9 platforms (H700, RK3399, RK3566, RK3588, S922X, SDM845, SM8250, SM8550, SM8650) e 42 devices que nenhum DTB nosso pode selecionar removidos. 352 arquivos, 8037 linhas. Sobrou só platform RK3326 + 14 devices que correspondem a um DTS em `projects/ArchR/devices/RK3326/linux/dts/rockchip/`.
- [~] **Splash sed rename**. O `archr-splash/package.mk` ainda faz `sed -i 's|TARGET=rocknix-splash|TARGET=archr-splash|'` no post_unpack porque o repo `archr-linux/archr-splash` ainda chama o binário internamente de `rocknix-splash`. Remover quando o fork upstream completar o rename.
- [ ] **Cases mortos em scripts/packages** S. Após a poda de platforms/, os scripts ainda têm `case ${DEVICE} in SM8250) ...; H700) ...; esac` que são dead branches inofensivos (DEVICE=RK3326 nunca casa). Limpar quando o arquivo for tocado por outro motivo.
- [ ] **Refator `runemu.sh`** M. 578 linhas (não 1500+ como o doc original sugeria), 18 case statements, 12 blocos emulator-specific. Refator em plugins por emulador continua sendo um ganho de manutenibilidade, mas a urgência é menor: o arquivo é navegável como está. Item orgânico, sem prazo.

### 2.6. Documentação no estilo ArchWiki

- [ ] **Wiki em `wiki.arch-r.io`** L. Páginas no padrão ArchWiki: Installation guide, Troubleshooting, Beginner's guide. Markdown estático, sem PHP.
- [ ] **`man archr` na imagem** S. Página `man(7)` curta explicando os comandos próprios (`archr-update`, `archr-flasher`, scripts em `/usr/bin/archr-*`).
- [ ] **`/etc/archr-release`** S. Arquivo padrão Arch (`/etc/arch-release` na original) para que ferramentas de detecção de OS reconheçam ArchR como família Arch.

### 2.7. Branding e copyright cleanup

- [ ] **Copyright headers** S. Onde o arquivo é 100% nosso, header só "ArchR". Onde herdou de LibreELEC/JELOS/ROCKNIX, manter o credit upstream + "Modified for ArchR (2026-present)". Patch em batch.
- [ ] **`os-release` `ID=archr` e `ID_LIKE=arch`** S. Para que terceiros detectem como Arch family. Hoje `ID=archr` está OK, falta `ID_LIKE`.
- [ ] **Refs upstream legítimas** N/A. Manter como estão: URLs de fork (`rocknix/rockchip-wlroots`), copyright headers herdados, comentários explicativos. Não-issue.

---

## Slots reservados (a preencher)

- `## 3. archr-joypad`
- `## 4. archr-flasher`
- `## 5. archr-website`
- `## 6. Kernel + drivers (mali_kbase, mali-bifrost, mipi-generator)`

Cada um ganha sua seção quando começarmos a auditoria.
