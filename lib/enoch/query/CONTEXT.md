# lib/enoch/query/

**Propósito:** Motor de consulta único, em Elixir: `parser.ex`, `evaluator.ex` (joins, predicados, negação, disjunção), `aggregate.ex`, `rules.ex` (regras não recursivas), `pull.ex` e `scan.ex` (invólucro público do scan do storage).

**Decisões:** D6 (motor único), D9 (agregados), D10 e D35 (regras), D28 (`:history`), D33 (cláusulas do Tickety, `txInstant`, `as_of` por data, `scan`), D36 (comparação entre tipos), D19 (limites de consulta). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s03: tudo. Regras recursivas, `d/entity` e componentes ficam para o e02.

**Fronteira:** Não gera SQL: o compilador de Datalog para SQL foi descartado (D6). Resolve a visibilidade do passado (D8, D16). Não conhece o formato físico do storage.

**Ponto de extensão:** As regras nomeadas vêm de listas de módulos (D35); regras avulsas na consulta continuam permitidas.

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
