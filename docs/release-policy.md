# Política de release do ArchR

Decisão registrada em 2026-06-23. Substituir este documento por edição direta quando a política mudar; nunca duplicar.

## Resumo

| Fase | Versionamento | Cadência | Quando muda |
|------|---------------|----------|-------------|
| Atual: pré-v2.0 | `vMAJOR.MINOR-rcN` (semver-RC) | sob demanda | RC5 vira 2.0 final |
| Pós-v2.0 | `YYYY.MM.patch` (Arch-style) | snapshot mensal | a partir de 2.0 |

## Por que mudar só depois de 2.0

A v2.0 é um marco de identidade: nova arquitetura (`new-arch` branch), Arch-ificação inicial (`ID_LIKE=arch`, archr-release, archr(7), Mesa 26.1.3, kernel 6.12.94), Flasher v1.3.2 estável, catálogo de 44 painéis. Mudar versionamento *durante* o ciclo RC quebraria a expectativa de quem está acompanhando a sequência RC1..RC5 e tornaria a release final indistinguível de um snapshot de manutenção.

Após 2.0, a v2.0 vira sentinel histórico e o sistema passa a ser efetivamente rolling. Versionar por data (Arch usa o mesmo modelo desde 2015) reflete melhor a realidade: cada snapshot é "o ArchR de junho de 2026", não "ArchR 2.1.7".

## Canais de release

| Canal | Conteúdo | Quem usa |
|-------|----------|----------|
| `stable` | snapshots mensais validados no R36S físico | usuário final |
| `next` | builds da branch `new-arch` (ou equivalente) após CI passar | testers, contribuidores |
| `dev` | builds noturnos de qualquer feature branch | mantenedores |

A variável `updates.branch` em `system.cfg` já existe (ver `archr-update`) e mapeia diretamente para esses canais. O endpoint `update.arch-r.io` deve passar a entender esses três valores e devolver imagem correspondente.

## Esquema de versionamento pós-v2.0

`YYYY.MM.PATCH` onde:

- `YYYY.MM`: ano e mês do snapshot (zero-pad no mês, `2026.07` e não `2026.7`)
- `PATCH`: contador de hotfix dentro do mesmo mês, começando em `01`. Snapshot regular é sempre `.01`. Hotfix urgente (CVE, regressão crítica) vira `.02`, `.03` etc.

Exemplos:
- `2026.07.01`: snapshot regular de julho.
- `2026.07.02`: hotfix dentro de julho.
- `2026.08.01`: próximo snapshot regular.

Tag git `vYYYY.MM.PATCH` (com `v` prefixo, consistente com nossa convenção atual `v2.0-rc4`).

## Cadência

Snapshot regular **uma vez por mês**, alvo: primeiro fim de semana. Justificativa:

- Mesa, kernel LTS e libretro cores liberam atualizações em ritmo mensal.
- Permite acumular testes do canal `next` antes de promover ao `stable`.
- Não sobrecarrega usuário com reflash semanal.
- Janela suficiente pra contribuidor testar uma feature antes de estabilizar.

Hotfix sai quando necessário, sem cadência fixa.

## archr-announce

Lista pública de anúncios obrigatórios. Mecanismo de entrega: **GitHub Releases body + RSS público + canal pinned no Discord da comunidade**. Sem mailing list SMTP (custo de manutenção alto, baixo retorno na escala atual).

### Convenção de tag no título da release

Cada release no GitHub tem tag obrigatória no início do body:

- `[Action Required]` exige passos manuais do usuário pós-update (ex.: re-pareamento de Bluetooth, migração de saves).
- `[Action Recommended]` é recomendação não-bloqueante (ex.: limpar cache antigo de shader).
- `[News]` é só anúncio, nenhuma ação.

Tooling consumidor (Flasher, archr-update) pode parsear essa tag e mostrar banner correspondente.

## Fluxo aprovado para subir um snapshot ao `stable`

1. Build noturno do `dev` passa em CI por 7 dias consecutivos sem regressão.
2. Promove para `next`: anúncio na release com tag `[News]`, instala em pelo menos 3 devices físicos diferentes (R36S original + 1 clone + 1 Soysauce).
3. Permanece em `next` por no mínimo 7 dias com feedback dos testers.
4. Promove para `stable`: anúncio com tag apropriada (Action Required se houver migração).

## Infra de distribuição

**Decisão registrada em 2026-06-23.**

**Mirror único: GitHub Releases.** Tudo que ArchR distribui (imagem `.img.gz` e pacotes `.pkg.tar.zst` quando 2.1 estiver pronto) sai pelo GitHub. Justificativa:

- Custo zero. GitHub serve a CDN, TLS e storage como bônus do repo público.
- Throughput global. CDN distribuída cobre o usuário onde estiver.
- Limites suficientes. 2 GB por asset cobre o maior pacote (kernel + initramfs). Sem limite total por release nem por conta.
- Já é o canal vigente. Reduzimos uma variável (não há "novo provedor para o usuário aprender").

**Google Drive (10 TB do mantenedor):** ficou de fora do runtime. Usos legítimos discutidos e aprovados:
- Backup das releases publicadas (via rclone após upload no GitHub).
- Archive histórico de versões antigas que saíram do GitHub.
- Assets pesados internos (BIOS de teste, gameplay para QA, scraper packs).
- Não serve como mirror pacman: URLs com hash, virus-scan warning em arquivos >25 MB, throttling, range requests inconsistentes.

**Cloudflare R2 ou Backblaze B2 como fallback:** avaliados, descartados por enquanto. Reavaliar se aparecer um problema concreto de disponibilidade do GitHub.

## Plano de update sem legacy

`archr-update` original faz POST para `update.arch-r.io`. Esse endpoint **nunca existiu**: o script nunca entregou update funcional. Significa que hoje o único caminho de update é reflashar a microSD com nova imagem baixada do GitHub Releases manualmente, e que **não há compatibilidade legada a preservar**.

A implementação de 2.1 (pacman como update real) é portanto clean slate:

1. Repo pacman `archr-linux/archr-repo` no GitHub.
2. Cada release nesse repo é uma tag tipo `repo-YYYY.MM.PATCH`, com todos os `.pkg.tar.zst` da snapshot + `archr-core.db` assinado.
3. Tags rolling `repo-stable`, `repo-next`, `repo-dev` mantêm sempre o snapshot mais recente do canal e ficam como alvo do `mirrorlist`.
4. `/etc/pacman.d/mirrorlist` aponta para `https://github.com/archr-linux/archr-repo/releases/download/repo-<canal>`.
5. `archr-update` reescrito como wrapper de `pacman -Syu` (algumas dezenas de linhas).
6. Reflashar continua sendo o caminho de upgrade para major bumps (kernel ABI, FHS, etc.); pacman cobre incrementais.

Primeira release ArchR a ter update via pacman será marco histórico. Pode ser RC5 ou v2.0 final, conforme prontidão da infra GPG e CI.
