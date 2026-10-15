# Repository graph (graphify) in EnochDB's ICM

`graphify` (installed on the system, today 0.9.91) extracts code and documents into a graph of nodes and edges in
`graphify-out/`. It serves to **find where to look** before opening or grepping a file, and to measure the
reach of a change. It does not judge, does not decide and is not proof.

## Rule

The graph is **derived from the repository (A4)**: it comes out of `graphify-out/`, does not enter git (`.gitignore`) and can
be deleted and rebuilt at any moment. A graph node never becomes evidence: the evidence is still
`arquivo:linha` read, as in [`../../PROCESS.md`](../../PROCESS.md). A graphify failure is a warning; it never blocks
a stage, iteration or gate. `graphify update` is only AST and document structure — **no LLM call**.

## Pieces

| Piece | Path | Role |
| --- | --- | --- |
| Config | [`jev-gates.json`](jev-gates.json), `conducao.graphify` | on/off, token budget, impact depth and limits |
| Runner | [`../_index/graphify.mjs`](../_index/graphify.mjs) | `estado`, `atualizar`, `consultar`, `impacto`, `resumo`; nothing here writes to `docs/` |
| omp hook | [`../../.omp/hooks/pre/graphify.ts`](../../.omp/hooks/pre/graphify.ts) | read guard, graph freshness and footer; see "Hooks" |
| Guard | `graphify pi guard path` (installed package) | the official `hook-guard`: tells the agent what the graph already knows before `read`/`grep`/`glob`/`bash` |
| Git hooks | `.git/hooks/post-commit`, `post-checkout`, `post-merge` | `graphify hook install`; rebuild the graph on every commit, branch switch and merge (local, no API) |
| Output | `graphify-out/` | `graph.json` (the graph, with `built_at_commit`), `graph.html`, `GRAPH_REPORT.md`, `manifest.json`, `cache/` |

graphify's merge driver is **not** registered: it exists to version `graph.json`, which here is
derived and ignored.

## How to call

```sh
graphify update .                          # rebuilds (incremental, no LLM, ~1 s)
graphify query "<question>" --seed <path-or-node> --budget 1500
graphify explain "<node>"                  # the node and its neighbourhood
graphify affected "<path-or-node>" --depth 1   # who depends on this (reverse traversal)
```

In `eval` (js), through the runner — it resolves budget, unknown seeds and tool failures:

```js
const G = await import(`${process.cwd()}/docs/_index/graphify.mjs`);
console.log(G.resumo(), G.consultar("transactor e escrita", { sementes: ["lib/enoch/tx/CONTEXT.md"] }));
```

- `estado()` — `existe`, `atual` (the graph's `built_at_commit` is HEAD), `nos`, `commit`, `head`.
- `consultar(pergunta, { sementes, orcamento })` — subgraph trimmed by the budget; `null` when there is no graph,
  node or answer. A seed the graph doesn't know brings down the whole command, so the runner filters the
  known ones first.
- `impacto(arquivos)` — `{ no, relacao, onde }[]` of the nodes that depend on the given files, without the files
  themselves. Approximate: it is a hint for the reviewer, not proof of side effect.
- `atualizar()` — rebuilds and returns `{ ok, motivo?, estado }`; it never throws.

## omp hooks

The hook `.omp/hooks/pre/graphify.ts` (omp ambient discovery; valid with the cwd in `EnochDB/`) does three things,
all derived and failing silently:

| Event | What it does |
| --- | --- |
| `tool_call` (`read`/`grep`/`glob`/`find`/`bash`) | **Guard.** Calls the installed graphify's `hook-guard` and returns, as trusted context, what the graph already has for that read, with the instruction to consult the graph before grepping a raw file. The guard is not copied: it comes from the installed package (`graphify pi guard path`), so updating graphify updates the guard. |
| `session_start`, `agent_end` | **Freshness.** Rebuilds the graph in the background when it is missing, is behind HEAD or the turn wrote a file. omp does not wait: the turn goes on. |
| `session_start`, `agent_end` | **Status.** Line in the footer: `graph: <n> nodes · at HEAD` (or `absent` / `behind HEAD` / `off`). |

graphify's guard kills no read: it injects the directive to consult the graph first. Whoever
decides to read a raw file is still the agent, and the cheapest read — asking the graph — is one
command away.

## In the ICM

| Point | What the graph does |
| --- | --- |
| `conduzir` | Rebuilds the graph and shows the `graph:` line in the panel. Each ready issue carries to dispatch a `# Graph` section with the subgraph of the paths the issue cites; a failure becomes `WARNING` in the panel and blocks nothing. |
| Subagent dispatch | The contract in `contextoCompartilhado` (see [`../_index/icm-conduzir.mjs`](../_index/icm-conduzir.mjs)) says to use `graphify query`/`explain`/`affected` before grepping a raw file, and that the graph points where to look without replacing the evidence. |
| `implementar.passo` | Before dispatching, it updates the graph and passes the hint to the slice owner. After measuring the changed files, it computes the `impacto` (reverse traversal) and writes it to `05_implement/handovers/jev.jsonl`; the verdict does not depend on it. |
| `implementar.fechar` | `implementacao.md` gains the line `reach, from the graphify graph`, with the accumulated iterations of the issue. |
| `duck` | The rubberduck locates through the graph before reading a file; the anchors it returns remain subject to the validation of `icm-duck.mjs`, which opens each `arquivo:linha`. |

## Limits and maintenance

- **Semantic extraction by LLM is not enabled.** `graphify extract --backend <gemini|kimi|claude|openai|deepseek|ollama>` and the assistant's `--update` create INFERRED edges, but they send documents and handovers off the machine — the same A5 issue as Jev's (see `docs/agents/jev.md` §Privacy). Enabling that is the owner's decision, with a chosen backend and a privacy warning; today the graph is only AST and structure.
- **Disable:** `conducao.graphify.ativo: false` in [`jev-gates.json`](jev-gates.json). The hook and the runner then do nothing, and the panel shows `graph: off`.
- **Remove:** `graphify hook uninstall` (removes the git hooks), delete `.omp/hooks/pre/graphify.ts` and `docs/_index/graphify.mjs`, and `rm -rf graphify-out`.
- **Without graphify installed:** the hook does not register the guard, `estado()` says `ativo` but the graph does not exist, and the panel shows `graph: absent`; nothing breaks.
- `graphify-out/` is in `.gitignore` and in `conducao.implementacao.ignorados`, so rebuilding the graph counts neither as a subagent change nor as a write outside the owner.
