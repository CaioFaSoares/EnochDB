# lib/enoch/adapters/

**Propósito:** Adaptadores de storage que acompanham o pacote: `memory.ex` (ETS) e `sqlite.ex` (SQLite via `exqlite`).

**Decisões:** D7 (fronteira), D16 (log imutável, estado atual, índices covering), D18 (`Memory`: histórico, atual e contador-base), D21 (recuperação do escritor), D23 (`exqlite`), D38 (decimal, contêiner). Texto em [`../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: `memory.ex` completo. s04: `sqlite.ex` completo.

**Fronteira:** O adaptador armazena e varre. Unicidade, visibilidade do passado e semântica de tipos moram no motor, não aqui (D14, D8, D36). Sem dialeto por banco para consultas (D6).

**Ponto de extensão:** Adaptadores externos (Postgres, MySQL) são extensões de storage e implementam `Enoch.Storage`; ficam no e02.

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../../docs/arquitetura.md`](../../../docs/arquitetura.md). Vocabulário em [`../../../CONTEXT.md`](../../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
