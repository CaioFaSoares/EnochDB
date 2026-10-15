---
sprint: s01-nucleo-enoch
titulo: Contrato de storage e adaptador Memory com transactor cru
epico: e01-nucleo-enoch
abertura: 2026-10-13
---

# s01-nucleo-enoch — Contrato de storage e adaptador Memory com transactor cru

**Objetivo:** entregar o contrato `Enoch.Storage` e o adaptador `Memory` (ETS com histórico e estado atual), com um transactor que aceita `add` e `retract` crus, validados por uma suíte de contrato, com a recuperação do escritor testada. O recorte das cinco sprints do e01 está em `01_grilling/handovers/decisoes.md` (D22).

**Épico:** [`../../epicos/e01-nucleo-enoch.md`](../../epicos/e01-nucleo-enoch.md)

**Fora de escopo:** schema, tempids, lookup refs, funções de transação, avaliador Datalog, adaptador SQLite e salvaguardas de memória. Pertencem às sprints seguintes do e01 (D22), ao e02 ou ao e03.

As etapas ficam em `NN_step/CONTEXT.md`, cada uma com `inputs/` e `handovers/`. O estado da sprint é
derivado das fichas das etapas; este arquivo não repete status de etapa.
