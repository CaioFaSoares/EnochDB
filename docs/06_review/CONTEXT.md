# 06_review — review before delivering

## Objective

Verify the implementation against the approved criteria and the local standards before preparing a delivery.

## Inputs

- `05_implement/handovers/implementacao.md` and `04_tickets/handovers/tickets.md`.
- Diff since the agreed base, canon and relevant ADRs.

## Process

1. Review separately the conformity with the local standards and the compliance with the spec.
2. For each finding, record evidence and choose: fix it now or open a work item; do not leave a relevant finding implicit. A fix goes into a fix issue in the tracker (criteria in `Acceptance criteria`), cited under a `## Fix issues` heading in `handovers/revisao.md`, and runs with `/icm implement` in this stage: owner's go, one path owner per file, journal in `handovers/jev.jsonl` and loop handover `handovers/correcoes.md`. `05_implement` is not reopened, even when the fix touches material delivered there.
3. Resolve divergences with an ADR by explicit decision, not by silent overwrite.
4. Write `handovers/revisao.md` with findings, fixes (fix issue and `correcoes` receipt under each finding) and pending items.
5. After the review and its fixes, assemble `handovers/pr.md` with scope, related items, affected decisions and verification commands actually executed.

## Outputs and human gate

Outputs: `docs/_sprints/{sprint}/06_review/handovers/revisao.md` and `pr.md`, plus `correcoes.md` when there were fixes. The owner accepts the outcome of the review before opening a PR; the absence of a tracker/chosen PR host does not authorize inventing a destination.

Before the human gate, run the `revisao` gate ([`../agents/jev.md`](../agents/jev.md)) and take the `receipt` to the owner.
