# 07_handoff — prepare the next session

## Objective

Let a next agent or collaborator start without depending on the memory of whoever closed the sprint.

## Inputs

- Handovers of the stages of this sprint.
- Canon, ADRs, glossary and tickets in their original locations.
- `../_templates/handover.md`.

## Process

1. State the likely mission of the next session and what must not be done.
2. Summarize the current state with paths and evidence; do not rewrite spec, tickets or decisions.
3. Record constraints that require an owner's decision, risks and questions still open.
4. List concrete steps, needed tools and skills that are really useful, without claiming they were executed.
5. Remove from the handover any secret, credential or personal data.
6. Update the sprint index only after the sheets show the observed state.

## Output and human gate

Output: `docs/_sprints/{sprint}/07_handoff/handovers/handoff.md`. The owner reads it as if he had not taken part in the work. If he needs missing context, complete the handover before closing the stage.

Before the human gate, run the `handoff` gate ([`../agents/jev.md`](../agents/jev.md)), which tests the zero context, and take the `receipt` to the owner.
