# lib/enoch/schema/

**Propósito:** Schema como dados: `data.ex` (forma canônica), `dsl.ex` (macros `entity`/`attr`, só açúcar), `bootstrap.ex`, `registry.ex`, `installer.ex` (instalação aditiva, compatibilidade, `deprecated`, renomear) e `migration.ex` (migração de dados versionada).

**Decisões:** D31 (dados e DSL), D29 (instalador, `deprecated`, renomear, migração), D11 (metadados de transação), D24 e D35 (registro legível por extensões), D36 (tipos). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s02: tudo, exceto `migration.ex`. s05: `migration.ex`.

**Fronteira:** O schema não grava datoms de aplicação; instalar o schema é uma transação como outra qualquer. A regra de unicidade e imutabilidade é imposta em `tx/`, não aqui.

**Ponto de extensão:** Cada módulo de aplicação ou extensão expõe uma lista de definições em dados; o instalador junta as listas e recusa colisão de nomes (D31).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
