# Plano canônico do EnochDB

## Estado

As decisões do grilling da s01 (D1 a D38) foram consolidadas na etapa `02_domain`: as de arquitetura em [`adr/`](adr/), as de escopo aqui, por ponteiro. O material inicial em [`canon/chat.md`](canon/chat.md) é contexto de exploração, não decisão aprovada. O status de cada ADR está no próprio arquivo.

## Decisões vigentes

Arquitetura (uma ADR por trade-off; o texto da decisão mora na ADR, não aqui):

- [ADR-0001](adr/0001-avaliador-datalog-unico-em-elixir.md): avaliador Datalog em Elixir como único motor de consulta.
- [ADR-0002](adr/0002-modelo-acumulativo-log-estado-atual-historico.md): modelo acumulativo, com log imutável, estado atual e histórico.
- [ADR-0003](adr/0003-memory-ets-contador-base-e-recuperacao.md): `Memory` em ETS, contador como base e recuperação.
- [ADR-0004](adr/0004-transactor-unico-regras-de-escrita-e-admissao.md): transactor único, regras de escrita e admissão.
- [ADR-0005](adr/0005-salvaguardas-de-consulta-e-memoria.md): consulta abusiva morre e a memória tem limite explícito.
- [ADR-0006](adr/0006-decimal-inteiro-escalado-e-ordem-dos-tipos.md): `:decimal` como inteiro escalado e ordem dos tipos.
- [ADR-0007](adr/0007-schema-em-dados-api-funcional-e-registro-por-modulos.md): schema em dados, API funcional e registro por módulos.
- [ADR-0008](adr/0008-subida-em-sete-passos-e-evolucao-do-schema.md): subida em sete passos e evolução do schema.
- [ADR-0009](adr/0009-pacote-unico-sqlite-exqlite-e-toolchain.md): pacote único, `exqlite` e toolchain.
- [ADR-0010](adr/0010-valor-derivado-nunca-e-fonte-de-verdade.md): valor derivado nunca é fonte de verdade.

Escopo e processo (sem ADR; a decisão está em [`decisoes.md`](_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md)):

- Divisão em três épicos e primeiro cliente real: D1, D2. Épicos em [`epicos/`](epicos/).
- Itens do chat com casa no e01 ou no e02: D5, D9, D10, D11.
- Critério de aceite do e01: D17.
- Cinco sprints do e01 e o que cada uma entrega: D22. A manutenção automática de atributo derivado entra no e01 (ADR-0010) e a sprint dela sai na `03_spec`.
- Tracker (GitHub Issues) e árvore de pastas: D38, em [`agents/README.md`](agents/README.md) e [`arquitetura.md`](arquitetura.md).

## Decisões superadas

Cadeias, do registro mais antigo ao vigente: D3 (só SQLite no e01) pela D7; D4 (compilar Datalog para SQL) pela D6; D8 (visibilidade no avaliador) pela D15 (visibilidade no adaptador, com intervalo por linha), que a D16 superou restabelecendo a D8 para as bases passadas; a primeira versão da D16 para o `Memory` (estruturas persistentes) pela D18; D5 (`:history` no e02) revisada pela D28; D30 (manutenção automática de derivado no e02) revogada em parte pelo dono em 2026-10-15, com a opção C no e01 (ADR-0010). O registro de cada uma está na ADR que as substituiu e em `decisoes.md`.
