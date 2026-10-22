# test/enoch/

**Propósito:** Testes que espelham `lib/enoch/`. A suíte de contrato roda aqui contra cada adaptador do pacote.

**Decisões:** D17 (critérios 1, 3 e 4), D22. Texto em [`../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: contrato inicial, leitura concorrente e a queda no meio da escrita (as duas provas da D18 e da ADR-0003). s02: tipos e unicidade. s03: avaliador. s04: contrato nos dois adaptadores. s05: telemetria e limites.

**Fronteira:** Os testes de contrato usam `Enoch.Storage.ContractCase`, não o duplicam (D24).

**Ponto de extensão:** Não.

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../docs/arquitetura.md`](../../docs/arquitetura.md). Vocabulário em [`../../CONTEXT.md`](../../CONTEXT.md). Os testes desta pasta existem desde a s01 e seguem a sprint da tabela acima.
