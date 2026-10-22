# lib/enoch/storage/

**Propósito:** Submódulos do contrato de storage. Hoje só `contract_case.ex`, a suíte de contrato reutilizável (`use Enoch.Storage.ContractCase`). O behaviour em si é `lib/enoch/storage.ex`, um nível acima.

**Decisões:** D24 (suíte reutilizável em `lib/`), D7 (contrato), D17 (critérios 1 e 3), D34 (versão do layout). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: suíte inicial e contador de linhas lidas. s04: a suíte roda nos dois adaptadores.

**Fronteira:** A suíte testa o contrato, não um adaptador específico. Cobre as quatro varreduras com o pushdown de cada índice, o modelo acumulativo, o banco de base antiga, o valor tupla e a ausência de consulta Datalog no contrato; leitura concorrente e recuperação ficam nas suítes do adaptador e do leitor. `as_of`, unicidade, tipos e decimal entram com as fatias que os implementam.

**Ponto de extensão:** Adaptadores externos executam esta mesma suíte (D24).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). O `contract_case.ex` existe desde a s01; a suíte ganha casos nas fatias seguintes.
