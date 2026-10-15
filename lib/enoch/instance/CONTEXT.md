# lib/enoch/instance/

**Propósito:** O que sobe por instância do banco: `supervisor.ex`, `owner.ex` (dono das tabelas, separado do transactor), `admission.ex` (fila limitada com estado fechado e aberto) e `boot.ex` (sequência de subida em sete passos).

**Decisões:** D32 (árvore por instância), D18 e D21 (dono das tabelas e `heir`), D27 (admissão), D34 (subida). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: os quatro, com os passos 1, 2, 3 e 7 da subida. s02: o passo do schema. s03: o registro de regras. s04: a versão do layout. s05: migrações, limites e telemetria.

**Fronteira:** Não guarda regra de transação nem de consulta. O dono das tabelas só guarda as tabelas do `Memory` e a base (D21). A subida não tem gancho para a aplicação (D34).

**Ponto de extensão:** Não. O registro automático de extensões é do e02 (D24).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
