# test/enoch/adapters/

**Propósito:** Os testes que são de um adaptador específico: `memory_test.exs` (a obrigatoriedade do `max_memory`, as duas tabelas ETS com o contador em `:atomics`, a ordem de escrita `2t+1 → histórico → atual → 2t+2` e a conferência do passo 2) e `memory_recovery_test.exs` (a recuperação depois da queda do transactor no meio da escrita). O que é do contrato está na suíte `Enoch.Storage.ContractCase`, rodada em `../storage/`.

**Decisões:** D18 (histórico, estado atual e contador), D20 (`max_memory`), D21 (recuperação) e D34 (passo 2); ADR-0003. Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: os dois, com o `Memory` completo. s04: o mesmo par para o SQLite.

**Fronteira:** Não duplica a suíte de contrato nem testa a árvore da instância; a admissão, a subida e a queda do dono ficam em `../instance/`.

**Ponto de extensão:** Não.

**Origem:** issues [#3](https://github.com/CaioFaSoares/EnochDB/issues/3), [#7](https://github.com/CaioFaSoares/EnochDB/issues/7) e [#11](https://github.com/CaioFaSoares/EnochDB/issues/11), e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md).
