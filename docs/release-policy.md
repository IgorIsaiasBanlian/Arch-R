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

## Compatibilidade com `archr-update` existente

`archr-update` atual já aceita `BRANCH` como variável de canal e faz POST para `update.arch-r.io`. Nenhuma mudança no cliente é necessária. O servidor precisa entender:

- `BRANCH=stable` (default): retorna último `YYYY.MM.PATCH` validado.
- `BRANCH=next`: retorna último build da branch principal.
- `BRANCH=dev`: retorna último build noturno (com warning de instabilidade).

Quando 2.1 (pacman como update real) estiver implementado, os canais migram naturalmente para repos pacman separados (`archr-core-stable`, `archr-core-next`, `archr-core-dev`).
