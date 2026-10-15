# 04_tickets — plan slices

## Objective

Split the spec into small, vertical and demonstrable deliveries, with blocks that represent real dependencies.

## Inputs

- `03_spec/handovers/spec.md` and, if it exists, `spec-tecnica.md`.
- Glossary and local ADRs.
- Tracker contract in [`../agents/README.md`](../agents/README.md).

## Process

1. Propose one slice per complete behavior path, not an isolated horizontal layer.
2. For each dependency, confirm that the blocking ticket is necessary to start the slice; avoid serializing parallel work.
3. For a broad migration, order expansion, batch migration and removal of the old form into separate slices.
4. Present titles, scope, acceptance criteria and edges for human approval before publishing.
5. Publish to the tracker defined in `../agents/README.md` only after the human approval of step 4; before that the proposal stays in `handovers/tickets.md`.

## Output and human gate

Output: `docs/_sprints/{sprint}/04_tickets/handovers/tickets.md`. The owner approves granularity and blocks. The stage closes only after publishing or explicitly recording that the work is a single pass and was marked `nao-aplicavel` according to the process rules.

Before publishing, run the `tickets` gate ([`../agents/jev.md`](../agents/jev.md)) and take the `receipt` to the owner.

After publishing, record in `handovers/tickets.md` the number of each issue as `#N`: it is that list that `/icm implement` reads to know which issues belong to the sprint ([`../agents/jev.md`](../agents/jev.md)). Dependencies between issues go in the `Dependências` section of the issue body, citing `#N`.

## When it does not apply

It may be `nao-aplicavel` for an isolated task that cannot be split without a cost greater than the work. The sheet explains the reason and records the risk of having no per-ticket trail.
