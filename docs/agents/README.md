# Conventions for agents — EnochDB

Before exploring or changing the project, read [`../../CONTEXT.md`](../../CONTEXT.md), [`../canon.md`](../canon.md) and the ADRs in [`../adr/`](../adr/) that touch the area. If a file does not exist yet or has no terms, carry on with the available facts; do not invent a decision just to fill the structure.

Use the vocabulary approved in the glossary in names, specs and tests. If a needed term is missing, note the gap for the domain stage. If the change contradicts an ADR, expose the conflict and ask for an explicit decision; do not silently rewrite the history.

## Epics and sprints

The work is grouped into epics in [`../epicos/`](../epicos/); each sprint points to its own in the `epico:` field of the sheet in `docs/_sprints/{sprint}/CONTEXT.md`. The derived state comes from `sh docs/_index/estado.sh`; do not replicate the status of an epic or a sprint in another file.

## Judgment (Jev)

Before declaring a stage ready, and before implementing when there is more than one path, consult the judgment gates: [`jev.md`](jev.md). Jev is advisory; a finding becomes a reading of the artifact, and closing a stage remains the owner's job. Questions and thresholds live only in [`jev-gates.json`](jev-gates.json).

## Repository graph (graphify)

Before opening or grepping a raw file, ask the graph: `graphify query "<question>"`, `graphify explain "<node>"`, `graphify affected "<node>"`. It is derived and approximate — it points to where to look and never replaces the `arquivo:linha` evidence. How it is built, what it does in the ICM and how to turn it off: [`graphify.md`](graphify.md).

## Tracker

The tracker is the GitHub Issues of the repository `CaioFaSoares/EnochDB` (decision D38 in [`../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md)). The `03_spec` and `04_tickets` stages publish there. An issue points to the documents by path instead of copying the content, and the folder architecture is in [`../arquitetura.md`](../arquitetura.md). The convention for labels and for dependencies between issues has not been decided yet: do not invent one; the default GitHub labels are enough for now.
