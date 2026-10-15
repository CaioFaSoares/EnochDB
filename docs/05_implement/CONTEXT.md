# 05_implement — execute a slice

## Objective

Deliver the authorized ticket without widening its scope. A task with no ticket or explicit authorization is not an input of this stage.

## Inputs

- `04_tickets/handovers/tickets.md` and the body of the ticket in progress.
- Technical mapping from `03_spec`, if it exists.
- [`../../CONTEXT.md`](../../CONTEXT.md), [`../canon.md`](../canon.md) and the relevant ADRs in [`../adr/`](../adr/).

## Process

1. Choose a ticket whose blocks are resolved and confirm its criteria before editing.
2. Write the behavior test first when there is an appropriate seam; implement only what is needed to pass.
3. Run focused tests during the work and the full suite once at the end.
4. Exercise the flow in the real program; an isolated test does not replace end-to-end evidence.
5. Record the ticket, commits, changed files, observed verifications and pending items in `handovers/implementacao.md`.
6. If new decisions or terms appear, update the canonical sources and flag any scope change for approval.

## Output and human gate

Output: `docs/_sprints/{sprint}/05_implement/handovers/implementacao.md`. The owner checks the evidence and pending items; do not declare a ticket or stage closed without the corresponding result.

Before asking for the gate, run the `implementacao` gate ([`../agents/jev.md`](../agents/jev.md)): a criterion with no recorded execution is a finding. Before starting, if there is more than one viable path, use `opcoes`.
