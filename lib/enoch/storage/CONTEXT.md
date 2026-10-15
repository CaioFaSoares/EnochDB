# lib/enoch/storage/

**Propósito:** Submódulos do contrato de storage. Hoje só `contract_case.ex`, a suíte de contrato reutilizável (`use Enoch.Storage.ContractCase`). O behaviour em si é `lib/enoch/storage.ex`, um nível acima.

**Decisões:** D24 (suíte reutilizável em `lib/`), D7 (contrato), D17 (critérios 1 e 3), D34 (versão do layout). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: suíte inicial e contador de linhas lidas. s04: a suíte roda nos dois adaptadores.

**Fronteira:** A suíte testa o contrato, não um adaptador específico. Cobre visibilidade, `as_of`, unicidade, ordem e decimal, tempids, lookup refs, `db` antigo e `queda no meio da escrita`.

**Ponto de extensão:** Adaptadores externos executam esta mesma suíte (D24).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
