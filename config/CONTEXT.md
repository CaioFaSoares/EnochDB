# config/

**Propósito:** Configuração do app OTP (`config.exs`, `runtime.exs`). A configuração de uma instância vai nas opções de `Enoch.start_link`, não aqui.

**Decisões:** D32 (instância por opções), D20 (`max_memory` obrigatório, `:infinity` explícito). Texto em [`../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01 base; s05 completa, com o app de exemplo.

**Fronteira:** Não guarda segredo nem dados de banco.

**Ponto de extensão:** Não.

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../docs/arquitetura.md`](../docs/arquitetura.md). Vocabulário em [`../CONTEXT.md`](../CONTEXT.md). O `config.exs` existe desde a s01; o `runtime.exs` e a configuração do exemplo entram com a s05.
