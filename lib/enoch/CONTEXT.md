# lib/enoch/

**Propósito:** Módulos de topo do núcleo: `repo.ex` (macro `use Enoch.Repo`), `application.ex`, `transactor.ex`, `db.ex` (banco como valor), `derived.ex` (`Enoch.verify_derived`), `telemetry.ex`, `storage.ex` (behaviour do adaptador). As regiões com vários módulos têm subpasta.

**Decisões:** D14 e D21 (transactor), D16 e D18 (banco como valor), D30 (`verify_derived`), D21 e D27 (telemetria), D7 e D34 (contrato de storage), D32 (repo). Texto em [`../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../../docs/_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).

**Sprint:** s01: `application`, `repo`, `transactor`, `db`, `storage`. s03: `derived`. s05: `telemetry` completo (s01 só o contador de linhas).

**Fronteira:** O transactor não resolve schema nem tipos (isso é de `tx/` e `schema/`). `db.ex` guarda referências e a base, não dados (D18). O `listen/1` do chat é de eventos e não existe no e01 (D5).

**Ponto de extensão:** `storage.ex` é o behaviour que adaptadores internos e externos implementam (D7, D24).

**Origem:** issue [#1](https://github.com/CaioFaSoares/EnochDB/issues/1) e o mapa em [`../../docs/arquitetura.md`](../../docs/arquitetura.md). Vocabulário em [`../../CONTEXT.md`](../../CONTEXT.md). Esta pasta ainda não tem código; este arquivo é a orientação para a implementação.
