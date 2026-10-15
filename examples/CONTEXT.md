# examples/

**Propósito:** Aplicação de exemplo que prova a experiência de ponta a ponta: projeto Mix novo que depende de `enoch`, schema com `:decimal`, `transact` com tempids, lookup refs, `cas` e metadados, `q` com agregado e regra, `pull`, `as_of`, evolução do schema da versão 1 para a 2 e execução em contêiner com volume.

**Decisões:** D17 (critério 2), D29 (migração v1 para v2), D34 (padrão de dados iniciais por upsert e reconciliador supervisionado), D38 (contêiner Alpine em dois estágios, NIF e WAL a verificar). Texto em [`../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s05.

**Fronteira:** É uma aplicação no sentido do glossário, não uma extensão. Não é gerador de projeto (fora do e01, item 31).

**Ponto de extensão:** Mostra como uma aplicação lista módulos de schema, funções e regras (D35).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../docs/arquitetura.md`](../docs/arquitetura.md). Vocabulário em [`../CONTEXT.md`](../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
