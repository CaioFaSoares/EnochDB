# lib/enoch/tx/

**Propósito:** Pipeline de transação: `expand.ex` (mapas viram operações), `resolve.ex` (tempids, lookup refs, cardinalidade, unicidade, imutabilidade), `function.ex` (behaviour das funções de transação), `validate.ex` (tipos, escala e normalização do decimal) e `report.ex`.

**Decisões:** D5 (tempids, lookup refs, funções), D14 (unicidade), D26 (imutabilidade), D12 e D13 (decimal), D35 (funções por lista de módulos), D36 (tipos). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: o mecanismo de `function.ex` sem conteúdo. s02: o restante. s05: funções com limites de tempo e de heap.

**Fronteira:** Não escolhe o storage nem o formato físico. Não arredonda decimal (D13); rejeita expoente e dígitos absurdos antes de qualquer aritmética (D38).

**Ponto de extensão:** `function.ex` é o behaviour que aplicações e extensões implementam; o registro é `{nome, módulo}` com nome espaçado, como `ledger/post` (D35).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
