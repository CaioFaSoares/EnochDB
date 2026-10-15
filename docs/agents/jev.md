# Jev in EnochDB's ICM

Jev (TypeSafe System One, `jev-latest`) is the **judgment layer** of this repository's ICM gates. It checks state, coverage and evidence before the owner reads it; it decides nothing. The research that grounds the design is in `_Aleph`: `_research/AlephBible/chat.md:379-508` (decisions D5–D13, constraints §6, results §7). Here it only says how it applies.

## Pieces

| Piece | Path | Role |
| --- | --- | --- |
| `judge` role | [`../../.omp/config.yml`](../../.omp/config.yml), `modelRoles.judge` | points omp's `eval` `judge()` to `typesafe/jev-latest` |
| Questions and thresholds | [`jev-gates.json`](jev-gates.json) | the **only** file the owner reviews; no question or threshold anywhere else |
| Runner | [`../_index/jev-gate.mjs`](../_index/jev-gate.mjs) | assembles the `state`, calls Jev, combines in code, returns the verdict |
| Conductor | [`../_index/icm-conduzir.mjs`](../_index/icm-conduzir.mjs) | derives the current stage, runs its gate, reads the open issues and assembles the subagent dispatch |
| Implementation | [`../_index/icm-implementar.mjs`](../_index/icm-implementar.mjs) | loop per issue: plan, go, step (dispatch + measurement + verification + Jev), closing |
| Backlog | [`../_index/icm-duck.mjs`](../_index/icm-duck.mjs) | validates anchors and writes `docs/_backlog/Bnn-*.md` |
| Command | [`../../.omp/commands/icm.md`](../../.omp/commands/icm.md) | `/icm [status\|continue\|duck\|implement] [sprint \| tema]` |
| Hook | [`../../.omp/hooks/pre/icm-jev.ts`](../../.omp/hooks/pre/icm-jev.ts) | write guard, gate freshness and stop turn; see "omp Hooks" |
| Receipt | `docs/_sprints/{sprint}/{etapa}/handovers/jev.jsonl` | one line per verdict and one per human decision; only `registrar`/`registrarDecisao` write |

The TypeSafe key lives in the omp credential (`typesafe`), never in a repository file.

## Gates

| Gate | When | What it checks |
| --- | --- | --- |
| `estado` | session start and before saying "ready" | sheets × folders × handovers; stage order in code, sheet × handover coherence by Jev |
| `grilling` | before the human gate of `01_grilling` | closed decision without origin; open question inside a closed decision |
| `dominio` | before the human gate of `02_domain` | ADR with only the solution (reads the ADRs linked by the handover); term without approval; decision without a home |
| `spec` | before the human gate of `03_spec` | each `Dn` decision from grilling appears in the spec and none is contradicted |
| `tickets` | before publishing | each spec item is delivered by some ticket |
| `implementacao` | before requesting the `05_implement` gate | each criterion has recorded execution; claim without command |
| `revisao` | before the `06_review` gate | finding without evidence or without destination; verification without command |
| `handoff` | before the `07_handoff` gate | zero-context test; claimed execution without proof |
| `opcoes` | when there is more than one viable path | each option × each criterion, ranking and tie in code |

## How to call

Inside omp's `eval` (JS), with cwd at `EnochDB/` for the `judge` role to apply:

```js
const g = await import(`${process.cwd()}/docs/_index/jev-gate.mjs`);
const r = await g.rodar({ judge, judgeBatch }, "spec", { sprint: "s01-nucleo-enoch" });
console.log(g.texto(r));
```

- `rodar(kernel, gate, args)` — `args.sprint` required, except in `opcoes` (`decisao`, `opcoes`, `criterios`, `contexto`). For `cobertura`, `args.itens` (`[{id, texto}]`) replaces automatic extraction.
- `registrar(r)` — appends the verdict to the stage's `jev.jsonl`; idempotent by the `recibo`.
- `registrarDecisao({sprint, etapa, recibo, decisao})` — **only after** the owner says `aceito`, `rejeitado` or `ajustado`. It is the `(veredito, decisao_humana)` pair of handoff D7; the agent does not choose it.

Verdict: `bloqueado` (tool, artifact, extraction or judge failed), `revisar` (there is a finding or it is uncertain) or `sem_achados`. `sem_achados` is **not** approval.

## omp Hooks

The hook `.omp/hooks/pre/icm-jev.ts` (ambient discovery by omp; applies with cwd at `EnochDB/`) makes the flow happen without the agent remembering. It **does not call Jev**: Jev keeps running in the `eval`, via `conduzir`; the hook guarantees that this happens at the right moment. Everything is derived from the sheets, the files and the receipts (A4).

| Event | What it does | Who is affected |
| --- | --- | --- |
| `tool_call` (`edit`/`write`) | **Guard.** Blocks writing to `conducao.guarda.proteger` (`jev-gates.json`, `docs/_index/`, the hook itself, `icm.md`), to `jev.jsonl` by hand and `status: fechado` in a stage sheet. With UI, the main agent asks the owner; without UI and in a subagent, it blocks. | everyone |
| `tool_result` (`edit`/`write`) | **Freshness.** If the current stage's handover (or an ADR, in `02_domain`) changed since the last receipt, it returns as trusted context the instruction to run the gate, once per turn. | main agent |
| `agent_end` | **Stop.** If there is still a gate without a receipt or outdated, it fires a turn (`sendMessage` with `triggerTurn`) with the same instruction. Once per state: it does not loop. | main agent |
| `session_start`, `agent_end` | **Status.** Footer line: `ICM <sprint> · <etapa> · <gate>: <frescor>`. | UI |

- **Freshness** (`frescor(sprint, etapa)` in `jev-gate.mjs`): compares the current hash of the artifacts the gate reads with that of the gate's last `veredito` receipt. `sem_recibo` and `desatualizado` warn; `sem_artefato` (nothing to judge) and `atual` do not. A blocked receipt is never written, so it does not count as a receipt.
- **The receipt is now born from `conduzir`.** It writes the stage gate's real verdict (idempotent by the `recibo`); the agent does not need to call `registrar`. The owner's decision remains only in `registrarDecisao`.
- **`dominio` reads the ADRs.** The gate reads `adrs.md` **and each `docs/adr/NNNN-*.md` it links** (`artefatos_citados`); a cited ADR that does not exist blocks. Editing just one ADR already makes the gate outdated.
- `05_implement` stays out of the warning: its receipt is born in `fechar` of `/icm implement`.
- The hook fails silently in `tool_result` and `agent_end` (it only stops warning) and closes in `tool_call`. To keep a single home, the list of protected paths lives in `jev-gates.json` (`conducao.guarda`).
- Maintenance: editing the system itself (`docs/_index/`, hook, `jev-gates.json`) requires the owner's confirmation; without UI, edit outside the ICM session.

## Conduzir: `/icm`

One command runs the short cycle: **panel → reading → owner's go → dispatch → gate again**.

| Who | Decides what |
| --- | --- |
| Code (`conduzir`) | current stage (first not closed), which gate to run, whether a handover is missing, candidate roles for the stage, issue readiness, "next" |
| Jev | probabilities: acceptance criterion, scope, pending block (given the stage state) and, among the candidates, the most suitable role |
| Owner | dispatch go, final role, owner of each file, human gate |

- **Issue ready** = acceptance criterion and scope clear and no pending block, all outside the uncertain range. Outside that it is `INCERTA` or `REFINAR`, and the action is to refine with the owner, never dispatch.
- **Suggested role** is advisory and restricted to `conducao.papeis_por_etapa`. Below `confianca_minima_papel`, or with `nenhum`, it stays without a suggestion and the owner chooses. This keeps handoff D5: Jev does not route the loop.
- **Dispatch** is the `task` argument assembled in code (`P.task`): shared context, one task per issue, the issue body via `gh issue view` (it is not copied), the cited paths that exist. It only leaves with the owner's go and with a declared owner per file.
- The tracker is GitHub Issues (D38). The conductor only reads (`gh issue list`); it neither creates nor closes issues.
- Nothing from the panel is persisted: state is derived on each call (A4). Receipts only enter `jev.jsonl` through `registrar`.

## Commands of `/icm`

`/icm [status|continue|duck|implement] [sprint | tema]`. Without an argument it is `status`, described above.

| Mode | What it does | Who closes |
| --- | --- | --- |
| `continue` | advances **one step** of the current stage (produce handover, resolve gate findings) and stops at the human gate | owner |
| `duck` | talks with the rubberduck, keeps what is worth it in `docs/_backlog/` | owner positions it (`git mv` to `01_grilling/inputs/` of a not-started sprint) |
| `implement` | loop over all the sprint's issues in `05_implement` | owner checks and closes the stage |

### Duck

- The proof comes from `11-discovery-rubberduck` (read-only). The item is only written by `docs/_index/icm-duck.mjs`, which **opens each `arquivo:linha` anchor and requires the excerpt on the line**; an anchor that does not match blocks the write. Without an anchor, the item counts as an idea (`sem_ancora: true`).
- Jev evaluates the item (`pergunta_delimitada`, `afirma_sem_ancora`) and suggests an open epic, only above `confianca_minima_epico`. It is advisory.
- Derived state: the item in `_backlog/` has no sprint; `sh docs/_index/estado.sh` lists them. See `docs/_backlog/README.md`.

### Implement

Flow: `plano` (read-only) → **owner's go** (`registrarGo`: role and owner of paths per issue) → `passo` repeated → `fechar`.

- **Which issues and in what order:** the `#N` cited in `04_tickets/handovers/tickets.md` (or explicit `issues`); topological order by the `#N` of the body's `Dependências` section; criteria are the `- [ ]` of the `Critérios de aceite` section. Everything extracted in code. An issue with no extractable criterion, a cycle or an open dependency outside the sprint becomes a block, not a guess.
- **One iteration** (`passo`): measures the git state (file hash) → dispatches the role (default `42-implementation-backend`, structured report) → measures again → runs the verification (`mix test`) → asks Jev, per criterion, whether there is observed execution that covers it → writes to `05_implement/handovers/jev.jsonl`.
- **Verdict (code):** `ok` only with verification at 0 and no criterion outside the clean range. Failed test or criterion without proof → `reiterar`, with the feedback assembled in code (criterion, reason, end of the test output) in the next prompt. Once the iterations are exhausted (`max_iteracoes`) → `bloqueada`.
- **Blocked, no negotiation:** writing outside the declared owner, to a `protegidos` path (includes `jev-gates.json`, `docs/_index/`, ADRs, canon), a subagent commit, `bloqueios` declared by it, a missing verifier, a failing subagent or judge. The issue and those depending on it stop; the independent ones continue.
- **What the loop never does:** commit, close an issue, change a stage's `status:`, edit what is protected, switch tools. Subagents run in series, one owner per file.
- **Resumption:** progress is derived from `jev.jsonl`; `/icm implement` in a new session continues from the next issue.
- **Closing:** `fechar` generates `implementacao.md` from the records (refuses to overwrite a hand-written file) and runs the `implementacao` gate over the `ok` issues. The measured verification is on the `verification` line; the criteria text is the subagent's declaration.

## How the agent uses it

1. **Before implementing:** `estado` and, if the ticket has more than one path, `opcoes`. There is no code consultation with Jev: it neither generates code nor chooses an action.
2. **Before declaring a stage ready:** its gate. Each `FINDING` and `UNCERTAIN` is read in the artifact (`arquivo:linha`) and resolved or recorded, as in `docs/06_review/CONTEXT.md` step 2. Jev's verdict is evidence, not truth.
3. **When delivering to the owner:** cite the `recibo` and what was confirmed by reading. Closing remains the owner's (`docs/PROCESS.md`, advancement rule).

## Constraints

Those of `_research/AlephBible/chat.md:457-466` apply in full. Those the code imposes:

- Jev only answers atomic yes/no (`bool`); combination, ranking, counting, stage order, file existence and date comparison are code.
- It never writes `status:`, closes a stage, generates artifact text nor chooses the next action.
- A key failure, network, missing artifact, pattern without an item or truncation produces `bloqueado` or a visible `TRUNCADO`, never a favourable verdict nor a fallback to another model.
- Do not claim unobserved verification: the gate's `texto` prints the model, `calibrado` and the receipt.

## Calibration state

`calibrado: false` in `jev-gates.json`. The thresholds (`faixa_incerta` 0.3–0.7) are Jev's doc generic range, not measured in this domain. While there are not enough `(veredito, decisao_humana)` pairs in `jev.jsonl`, the `FINDING` is a lead to read, not to block. The omp catalogue only exposes `jev-latest`; pinning `jev-1.13.0` stays pending until there is a calibrated threshold (handoff constraint 6).

## Privacy

The `state` leaves the machine for TypeSafe. An EnochDB handover carries product decision; it is handoff open question A5 (`chat.md:449`). Do not pass secrets, credentials or personal data to the gate; `07_handoff` already forbids that in handovers.
