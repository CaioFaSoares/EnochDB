---
description: Drives the EnochDB ICM with Jev: status, continue, duck (backlog), decidir (the owner's decision on the receipt) and implement (sprint loop)
argument-hint: "[status|continue|duck|decidir|implement] [sprint | duck topic | aceito|rejeitado|ajustado]"
---

Drive the EnochDB ICM. Mode: `$1` (empty = `status`). Remaining arguments: `$@[2]`. Jev and module rules: `docs/agents/jev.md`. Execute **only the section of the requested mode**. The session cwd must be the repository root.

Rules that hold in every mode: the panel and any Jev verdict are advisory (every `FINDING` or `UNCERTAIN` is confirmed in the artifact before it becomes your own words); `BLOCKED` is a tool, artifact or state failure: say which one and stop on that front; the order of the stages and the "next" come from the code; closing a stage and an issue, moving a file out of `_backlog/` and committing are owner-only acts. Reply in English, short.

Graph (graphify, `docs/agents/graphify.md`): `conduzir` rebuilds `graphify-out/` and the panel shows the line `graph:`. Before opening or grepping a raw file, use `graphify query "<question>"`, `graphify explain "<node>"` or `graphify affected "<node>"`; the graph is derived and approximate, so it is a hint about where to read and never becomes evidence: the proof remains the `arquivo:linha` that was read. A `WARNING` of a missing or stale graph blocks nothing: run `graphify update .` and carry on.

## status (default)

```js
const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);
const sprint = "$2" || c.sprints().at(-1);
globalThis.P = await c.conduzir({ judge, judgeBatch }, { sprint });
console.log(c.painel(P));
```

Show the owner: current stage, verdict and gate receipt, issues ready and being refined (with the Jev question that failed) and the next step. `conduzir` writes the gate receipt to `handovers/jev.jsonl` (idempotent by receipt); report `P.gate.registrado`. Do not call `registrar`. If `P.task` exists, ask (`ask`) for the go, the role (Jev's suggestion is only a suggestion) and the **owner of each file**, one per file; with the go, call the `task` tool with `P.task`. Without the go, nothing is dispatched.

## continue

Advance **one step** of the current stage, without skipping a human gate.

1. Run the panel above (without dispatching). Take `P.proximo[0]`.
2. If it is **produce the handover** of the stage: read the contract `docs/<etapa>/CONTEXT.md`, its inputs and the issue in focus (`gh issue view`); write the handover with the candidate roles from `P` when you need reading or review. One writer per file.
3. If it is **gate findings**: open each cited artifact, confirm, fix or record each one; run the gate again.
4. If the next one is **take the receipt to the owner**: stop and present the receipt; the human gate is the owner's. If it is `05_implement`, the path is `/icm implement`, not this mode.
5. Finish by showing the new panel and what is missing for the human gate. `conduzir` has already written the gate receipt to `handovers/jev.jsonl`; do not call `registrar` with `P.gate`. `registrarDecisao` only after the owner decides. The omp hook (`.omp/hooks/pre/icm-jev.ts`) warns when the artifact changes after the receipt: run the gate again.

## duck

Conversation to explore `$@[2]` and, if it is worth it, keep it in the backlog. The backlog is `docs/_backlog/` (see `docs/_backlog/README.md`); positioning it in a sprint that has not started yet is moving the file, an owner-only act.

1. Talk with the owner to delimit **one** doubt. When you need proof, call the role `11-discovery-rubberduck` (`task` tool, `agent: "11-discovery-rubberduck"`) with the doubt in one sentence, what has already been tried and the authorized paths; it returns `arquivo:linha` anchors. Do not answer by analogy: without an anchor, say "I did not find it".
   Ask rubberduck to locate it through the graph (`graphify query`/`explain`) before reading a file; the anchors it returns are still subject to validation by `icm-duck.mjs`, which opens each `arquivo:linha`.
2. When the owner asks to keep it, assemble the item and the **preview without writing**:

   ```js
   const B = await import(`${process.cwd()}/docs/_index/icm-duck.mjs`);
   globalThis.V = await B.prever({ judge, judgeBatch }, { titulo, pergunta, resumo, evidencias: [{ ancora: "arquivo:linha", trecho: "texto exato da linha" }], contradicoes: [], em_aberto: [] });
   console.log(B.texto(V));
   ```

   `BLOCKED` (an anchor that does not match, a failed judge) blocks the write: fix the anchor or record it without it as an idea. Show the owner the preview and the suggested epic; he may change the title, the cut or discard it.
3. With the owner's ok (`ask`), `B.gravar(V)`. Report the path, the sprints that have not started yet (`V.candidatas`) and the command to position it: `git mv docs/_backlog/<arquivo> docs/_sprints/<sprint>/01_grilling/inputs/`. Do not move it yourself.

## implement

Implementation loop over **all the issues of the sprint**, one at a time, in dependency order, with verification and Jev on every iteration. Only valid in `05_implement`. Mechanism and guarantees: `docs/agents/jev.md`, section Implement.

1. **Plan and go.** Discover the sprint (`$2` or the most recent one) and run:

   ```js
   const I = await import(`${process.cwd()}/docs/_index/icm-implementar.mjs`);
   globalThis.I = I;
   globalThis.SPRINT = "$2" || (await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`)).sprints().at(-1);
   const p = await I.plano({ sprint: SPRINT });
   console.log(I.painel(p)); console.log(JSON.stringify(p.proposta));
   ```

   `BLOCKED` here stops the mode (wrong stage, no `#N` in `tickets.md`, issue without criteria, cycle). If `p.go` already exists, resume from step 3. Otherwise, show the owner, via `ask`, the order, the role and the **path owner of each issue** (start from `p.proposta`; he edits it), and the iteration limit (`p.max_iteracoes`). Without a declared path owner, there is no go. With the go: `I.registrarGo({ sprint: SPRINT, itens: [{ numero, papel, dono: ["lib/...", "test/..."] }] })` and set `status: em-curso` in the sheet `docs/_sprints/<sprint>/05_implement/CONTEXT.md` if it is still `vazio`.

2. **Verifier.** The loop runs `conducao.implementacao.verificacao` from `docs/agents/jev-gates.json` (today `mix test`, requires `mix.exs`). A missing tool is `bloqueada`, never a fallback.

3. **Loop.** Repeat one cell per step, with `timeout: 1800`:

   ```js
   globalThis.R = await I.passo({ judge, judgeBatch, agent }, { sprint: SPRINT });
   console.log(JSON.stringify(R, null, 1));
   ```

   - `iteracao` with `veredito: "ok"`: next. `"reiterar"`: the feedback has already been recorded; call it again. `"bloqueada"`: the reason is in `R.motivos`; the loop moves on to the independent issues by itself.
   - Between issues, tell the owner one line: `#N it/max veredito`, files and `testes`. Do not interrupt to ask, unless `R.acao` is `bloqueado` or `sem_go`.
   - `R.impacto` lists the nodes that depend on the files the iteration changed (reverse graph traversal, outside those files). Read it before calling the issue `ok`: a node outside the declared owner is a hint of a side effect for the owner, not a block nor a proof; the record goes to `jev.jsonl` and to `implementacao.md`.
   - Stop and bring it to the owner if the same reason blocks two issues in a row, or if `wrote outside the declared owner`, `touched a protected path` or `changed git's HEAD` appears: they are contract violations, not test failures.
   - `R.acao === "fim"`: go to step 4.

4. **Closure.** `await I.fechar({ judge, judgeBatch }, { sprint: SPRINT })` writes `05_implement/handovers/implementacao.md` (derived from `jev.jsonl`) and runs the `implementacao` gate. Show the owner: issues `ok`, issues `bloqueada` or pending with the reason, the verdict and the gate receipt, and what was **not** done: no commit, no issue closed, stage still `em-curso`. The human gate of `05_implement` and the commit are the owner's. Do not relay the text of the criteria the subagent declared as if it were verified: the measured verification is the `verification` line of the file.

## decidir

Record the owner's decision on the receipt he saw, for the gate of the current stage, and propagate the result. Argument: `$2` ∈ `aceito|rejeitado|ajustado`, said by the owner; without it, stop and ask. The agent never chooses the decision. Here `$2` is the decision, never the sprint: the sprint is always the most recent one.

1. Check freshness **without calling Jev** (do not run `conduzir`, which writes a new receipt if the text changed):

   ```js
   const c = await import(`${process.cwd()}/docs/_index/icm-conduzir.mjs`);
   const g = await import(`${process.cwd()}/docs/_index/jev-gate.mjs`);
   globalThis.SPRINT = c.sprints().at(-1);
   globalThis.ETAPA = c.etapaAtual(g.fatosDoSprint(SPRINT)).nome;
   globalThis.F = g.frescor(SPRINT, ETAPA);
   console.log(JSON.stringify(F));
   ```

   With `F.estado !== "atual"`, stop: tell the owner the state (`desatualizado` lists `F.mudados`) and that `/icm status` writes the new receipt for him to see before deciding. With `atual`, the receipt is `F.recibo` (the last `veredito` of `jev.jsonl`) and `F.veredito` is what the owner saw.
2. Record the decision on that receipt:

   ```js
   console.log(g.registrarDecisao({ sprint: SPRINT, etapa: ETAPA, recibo: F.recibo, decisao: "$2" }));
   ```

3. Only with `aceito` or `ajustado`: replace `Status: proposta` with `aceita` in the ADRs the receipt covers (the `docs/adr/NNNN-*.md` linked by the stage handover). With `ajustado`, only in the ones the owner lists. With `rejeitado`, nothing changes: the owner says what to fix.
4. Still with the stage open, write the receipt of the final text: changing the status of the ADRs changes the artifacts the gate reads, and after the sheet is closed `conduzir` moves to the next stage and no longer runs that gate. The new receipt has no decision: the agent does not copy it from step 2.

   ```js
   globalThis.R = await g.rodar({ judge, judgeBatch }, F.gate, { sprint: SPRINT });
   console.log(R.veredito, R.recibo, JSON.stringify(g.registrar(R)));
   ```

   Show the owner the text diff (`git diff -U0 -- docs/adr`, only the `Status:` lines when nothing else changed) and ask (`ask`) whether he records the decision also on the new receipt. Only with his yes: `g.registrarDecisao({ sprint: SPRINT, etapa: ETAPA, recibo: R.recibo, decisao: "$2" })`. Without the yes, the receipt stays without a decision and you say so.

5. Closing the stage is an owner-only act: ask (`ask`) whether he closes it. Only with a yes, set `status: fechado` in the sheet `docs/_sprints/<sprint>/<etapa>/CONTEXT.md`; the hook asks for the owner's confirmation on that edit. Closing the issue and committing remain with the owner.
6. Show the panel, with the sprint explicit (the `status` snippet uses `$2`, which here is the decision): `globalThis.P = await c.conduzir({ judge, judgeBatch }, { sprint: SPRINT }); console.log(c.painel(P));`. Tell the owner on which receipt each decision is (steps 2 and 4) and that the order is decision, status, final receipt, decision on it, closure.
