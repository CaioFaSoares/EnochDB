# test/enoch/storage/

**Propósito:** A suíte de contrato (`Enoch.Storage.ContractCase`) rodando em cada adaptador: no `Memory` e em um adaptador de teste de fora de `lib/enoch/adapters`.

**Decisões:** D24 (suíte reutilizável), D7 (fronteira), D17 (critérios 1 e 3). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: contrato no `Memory` e no adaptador de teste. s04: contrato nos dois adaptadores do pacote.

**Fronteira:** Não duplica a suíte nem testa um adaptador específico; o que é só do `Memory` fica em `../adapters/memory_test.exs`.

**Ponto de extensão:** É o caminho pelo qual um adaptador externo prova o contrato (D24).

**Origem:** issue [#3](https://github.com/CaioFaSoares/EnochDB/issues/3) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md).
