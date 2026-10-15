# 01_grilling — clarify and decide

## Objective

Turn the request or the input hypothesis into decisions the owner recognizes as his own. No code or ticket is produced in this stage.

## Inputs

- Material specific to this run in `docs/_sprints/{sprint}/01_grilling/inputs/`.
- [`../../CONTEXT.md`](../../CONTEXT.md) (repository root): approved vocabulary.
- `../canon.md` and `../adr/`: current decisions and alternatives already evaluated.
- Links to historical material, without copying content from other sources.

## Process

1. Identify actors, need, constraints and observable outcome.
2. Interrogate ambiguities until each point is a closed decision, discarded with a reason, or open with the missing information.
3. Flag any conflict with the canon or an ADR; do not silently replace a current decision.
4. Record the three lists in `handovers/decisoes.md`, with paths to the sources read.

## Output and human gate

Output: `docs/_sprints/{sprint}/01_grilling/handovers/decisoes.md`.

Before the human gate, run the `grilling` gate ([`../agents/jev.md`](../agents/jev.md)) and take the `receipt` to the owner.

The owner reads and confirms the closed decisions. If any looks like an invention of the agent, it goes back to discussion. Only after that acceptance may the sheet close.

## When it does not apply

It may be `nao-aplicavel` when the work already arrives with approved and traceable decisions, with no product or architecture question. The sheet must point to that source. Do not use this exception to avoid a hard decision.
