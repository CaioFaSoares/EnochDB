# 02_domain — consolidate decisions and vocabulary

## Objective

Give the decisions confirmed in the grilling a durable home, separate from the handover that produced them.

## Inputs

- `01_grilling/handovers/decisoes.md` of the current sprint.
- `../../CONTEXT.md` (root): domain terms already approved.
- `../canon.md` and `../adr/`: existing decisions and numbering.

## Process

1. For each decision, determine whether there is an architectural trade-off that needs an ADR. An ADR explains the pain first, records the options considered and closes the decision and its consequences.
2. Number ADRs in sequence as `NNNN-slug.md`; do not silently change an earlier decision. A reversal must point to the superseded record.
3. Add to the glossary only approved terms, with a definition and synonyms that must be avoided where there are any.
4. Note changes in the canon and point to the corresponding ADR; preserve the trail of superseded decisions.
5. Record in `handovers/adrs.md` which decisions and terms were consolidated and their paths.

## Output and human gate

Output: handover in `docs/_sprints/{sprint}/02_domain/handovers/adrs.md`, local ADRs and glossary updates. The owner checks whether the context of each ADR describes the pain, not only the solution, and approves the terminology before closing the stage.
