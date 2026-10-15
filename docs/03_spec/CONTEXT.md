# 03_spec — specify the outcome

## Objective

Convert approved decisions into verifiable behavior, without reopening the interview or adding scope by assumption.

## Inputs

- `01_grilling/handovers/decisoes.md` and `02_domain/handovers/adrs.md` of the current sprint.
- Glossary, canon and local ADRs.
- Tracker only if there is an approved decision that identifies it.

## Process

1. Write user stories or use cases and observable acceptance criteria. Every decision closed in the grilling appears as a requirement or as out of scope.
2. Record the verification seams and prefer the existing ones over new ones.
3. If there is already code, do the optional mapping between each requirement and its implementation points; keep it in `handovers/spec-tecnica.md`.
4. Keep the body of the spec in `handovers/spec.md`. The tracker is the one defined in `../agents/README.md`: an issue points to the spec by path, without copying it, and this folder keeps the criteria the run needs to carry.
5. Update canon, ADRs or glossary if the specification reveals a new decision; do not treat a hypothesis as authorization.

## Output and human gate

Output: `docs/_sprints/{sprint}/03_spec/handovers/spec.md` and, when there is a codebase, `spec-tecnica.md`. The owner checks coverage of every decision, testable criteria and scope limits.

Before the human gate, run the `spec` gate ([`../agents/jev.md`](../agents/jev.md)): every decision of the grilling must appear as a requirement or as out of scope, and the `receipt` goes to the owner.

## When it does not apply

It may be `nao-aplicavel` when a complete, approved spec is already the input of the work. The sheet points to that spec; do not create a second one.
