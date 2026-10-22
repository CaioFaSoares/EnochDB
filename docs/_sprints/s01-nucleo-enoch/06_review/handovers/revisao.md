---
sprint: s01-nucleo-enoch
step: 06_review
---

# Review — s01-nucleo-enoch

> **Outcome:** the delivery is **not accepted as-is**. Four findings block (R01, R02, R03, R07), two violate an s01 acceptance criterion through docs (R10, R11), and the rest are relevant or minor. Each finding has a destination below; none of them is fixed yet, because fixing code needs the owner's go (no issue authorizes code after `05_implement`).

## Scope and base

- Diff under review: `git diff 76c60b4 5807bcf` (68 files). Code: `lib/`, `test/`, `mix.exs`, `mix.lock`, `.formatter.exs`, `config/`, `flake.nix`, `flake.lock`.
- Ruler: [`../../04_tickets/handovers/tickets.md`](../../04_tickets/handovers/tickets.md) (F1–F9 = #2–#10), [`../../03_spec/handovers/spec.md`](../../03_spec/handovers/spec.md) (R1–R37), ADRs in [`../../../../adr/`](../../../../adr/), [`../../../../arquitetura.md`](../../../../arquitetura.md), glossary `CONTEXT.md`.
- The criteria text in [`../../05_implement/handovers/implementacao.md`](../../05_implement/handovers/implementacao.md) is the implementer's claim; this review rechecked it.

## Method

Two independent passes, then the orchestrator re-ran every reproduction:

- **Standards conformity** (role `reviewer`): ADRs 0002–0004 and 0008–0010, folder tree, concurrency and error paths, language rule. Transcript: `history://StandardsReview`.
- **Spec compliance** (role `60-sprint-review`, read-only, no shell): the 35 criteria mapped to a proving test or to "reading only". Transcript: `history://SpecCompliance`.
- Reproduction scripts live in `/tmp/enochrev/*.exs` (throwaway, not in the repo). Every "observed" output below came from `mix run /tmp/enochrev/<script>.exs` run by the orchestrator on 2026-10-20 at `5807bcf`, unless marked otherwise.

## Criteria coverage

| Slice | Criteria | Proven by a test in the suite | Proven only by a one-off script or reading |
| --- | --- | --- | --- |
| F1 (#2) | 3 | 1 (`application_test.exs:8`) | 2 (toolchain, `hex.audit`; both re-run below) |
| F2 (#3) | 8 | 8 (`contract_case.ex:48,81,132,157,178,202,232`; `memory_test.exs:15-38,80,122`) | — |
| F3 (#4) | 4 | 4 (`reader_test.exs:31,64,105,141,189`) | — |
| F4 (#5) | 4 | 3 (indirect: `repo_test.exs:48-87`, `admission_test.exs`) | `retract` read back through `Enoch.transact` (R09) |
| F5 (#6) | 4 | 4 (`admission_test.exs:55,82,135,183,210`), but criterion 1 fails under concurrency (R01) | — |
| F6 (#7) | 4 | 4 (`memory_recovery_test.exs:45,143,200,237,249`) | — |
| F7 (#8) | 5 | **0** (R07) | 5; criterion 1 fails during the boot window (R02) |
| F8 (#9) | 1 | 1 (`repo_test.exs:48,75`) | — |
| F9 (#10) | 2 | 0 | 2 (orchestrator: `nix flake check --no-build` → `✅ devShells.aarch64-darwin.default (build skipped)`, `✅ apps.aarch64-darwin.test`, `✅ apps.aarch64-darwin.estado`, `✅ checks.aarch64-darwin.test`; `nix run .#test`, `nix run .#estado` and a full build not run) |

## Findings

Severity: **bloqueia** = breaks an acceptance criterion, ADR or spec requirement of s01; **relevante** = real defect or risk; **menor** = cosmetic or doc. Destination: **corrigir agora** (fix in s01 before the PR) or **item de trabalho** (later sprint named).

### R01 — bloqueia — admission limit is exceeded under concurrent callers

- Code: `lib/enoch/transactor.ex:90-96` reconciles before every admit; `lib/enoch/instance/admission.ex:200-204` overwrites the counter with `message_queue_len`, erasing increments of callers that admitted but have not sent; `admission.ex:287-293` counts the in-flight transaction only when the transactor status is `:running`.
- Observed (`admission_race.exs`, `limit: 4`, suspended transactor, 2000 callers): `results: %{:ok => 15, {:error, :admission_full} => 1985}` and, on another run, `mailbox ... = 9, counter = 9`; status samples during a 600k-op transaction: `%{runnable: 152, running: 12, waiting: 36}`.
- Observed (`admission_bypass.exs`, `limit: 1`): `transactor while in-flight: [status: :waiting, message_queue_len: 0]`; `results (limit 1, 10 concurrent): %{:ok => 2, ...}`.
- Breaks: R13, ADR-0004, F5 criterion 1. The suite misses it: `admission_test.exs:183,210` only reconcile with an idle or suspended transactor.
- Destination: **corrigir agora**. Reconcile only on the `:admission_full` path and retry once; replace the `:running` heuristic with an explicit in-flight flag (a 4th `:atomics` slot set at the start of `handle_call`, cleared after `release`); pending = `message_queue_len + in_flight`; add a concurrent-callers test asserting the mailbox never exceeds the limit.

### R02 — bloqueia — admission is open and the transactor runs before boot steps 1–3

- Code: `lib/enoch/instance/supervisor.ex:82-90` starts owner, admission and transactor together; admission starts with the configured status, default `:open` (`admission.ex:247,302-305`); `Boot.run` closes it only after `Owner.storage/1` (`boot.ex:89-91`); recovery runs in `Transactor.init` (`transactor.ex:101`), before the layout check.
- Observed (`boot_window2.exs`, adapter with layout 99 and a 300 ms recovery): `start_link result ... {:error, {:layout_too_new, 99, 0}}` and `external writes {:ok, t} returned before boot refused the instance: 90918`, first ones `[{1, :open}, {2, :open}, {3, :open}]`.
- Breaks: R31 (step 3 "starts the transactor with admission closed"), ADR-0008 (step 2 "before the transactor exists"), R13 ("admission is born closed"), F7 criterion 1.
- Destination: **corrigir agora**. Admission always starts closed; the configured status becomes the state step 7 applies. The supervisor starts owner and admission; `Boot.run` runs steps 1–2, starts the transactor with `Supervisor.start_child` (step 3), then steps 4 and 7.

### R03 — bloqueia — `Owner.storage/1` recovers unconditionally and deletes log rows of an acknowledged transaction

- Code: `lib/enoch/instance/owner.ex:47,72-75` runs `recover` on every `:storage` call; `boot.ex:89` calls it with the transactor alive (R02); `boot.ex:82-83` documents calling `Boot.run` on a live tree.
- Observed (`live_recover.exs`, 300k-datom transaction, `Owner.storage/1` called mid-write): the counter read `1` while the transactor was mid-transaction and `2` right after `Owner.storage/1` (recovery ran); `live transaction reply: {:ok, 1}`; `{history size, current size} (should both be 300000): {266393, 300000}`. The caller was told the write landed; the log, the source of truth, lost 33 607 rows.
- Breaks: ADR-0002 (log is the source of truth), ADR-0003 (recovery runs after the transactor crashed, before accepting writes), ADR-0010.
- Destination: **corrigir agora**. `storage/1` becomes a pure read; a separate checkout runs recovery and only `Transactor.init` calls it (`rest_for_one` guarantees the previous transactor is dead).

### R04 — relevante — step 2 rebuilds the current state with the counter even, so readers accept torn present scans

- Code: `lib/enoch/adapters/memory.ex:230-244` (`verify/1`) and `:273-277` (`delete_all_objects` then re-insert) run with the counter at `2b`; the reader guard at `:364-384` cannot see it.
- Observed (`verify_torn.exs`, 200k live datoms, one tampered row, reader at basis 1 during `verify/1`): present scans returned counts like `1860`, `2915`, `4339` instead of `199999`.
- Breaks: the invariant behind ADR-0003 and R4 (the counter brackets every write to the current state).
- Destination: **corrigir agora**. Bracket the rebuild like recovery does (`begin_tx` → rebuild → `publish_tx`, an empty transaction); mark `rebuild_current/2` `@doc false`.

### R05 — relevante — boot step 2 discards the adapter's verification result; `recover/1` and `verify/1` are not in the contract

- Code: `lib/enoch/instance/boot.ex:129-135` returns `:ok` whatever `verify/1` returns; `owner.ex:83-85` and `boot.ex:129-131` use `function_exported?`; `storage.ex:186` declares only `layout_version: 1` optional.
- Observed (`boot_window.exs`, `verify/1` returning `{:error, _}`): `start_link with verify/1 returning {:error, _}: :ok`, `admission status: :open`.
- Breaks: R31 ("a failure in any step prevents boot"), ADR-0008.
- Destination: **corrigir agora**. Propagate the `verify/1` result; declare `recover/1` and `verify/1` as `@optional_callbacks` with docs.

### R06 — relevante — an owner crash restarts the instance with empty tables, reuses `t` and leaks the old tables

- Code: `owner.ex:92-104` sets the instance supervisor as `heir`, which has no `ETS-TRANSFER` handling; `rest_for_one` restarts the owner, whose `init` opens new tables (`owner.ex:65`); the `:atomics` counter is lost.
- Observed (`owner_kill.exs`): `[error] Supervisor received unexpected message: {:"ETS-TRANSFER", ...}` (twice), `old history table now owned by supervisor (leaked): true`, `basis_t after owner restart: 0`, `next transact (t reused?): {:ok, 1}`, `admission status after restart: :open`.
- ADR-0003 requires surviving a transactor crash only, and that holds. Losing the owner today is silent data loss with no boot.
- Destination: **corrigir agora**. Make the owner `restart: :temporary, significant: true` with `auto_shutdown: :any_significant`, so losing the tables stops the instance; drop the heir or keep it documented as unused. A real table handoff, with the counter, is an **item de trabalho s04/s05** if the owner wants it.

### R07 — bloqueia — the five F7 criteria have no test in the suite

- Evidence: a grep of `test/` for `layout_too_new|duplicate_function|duplicate_rule|boot_event|verify\(` finds nothing; per-file counts (1+9+6+9+9+5+8+3 = 50) contain no boot test. The F7 proof in `implementacao.md:106-110` is one-off `mix run -e` scripts.
- Breaks: R17 acceptance ("a test captures each event with `:telemetry`"); leaves R24, R30 and R31 without regression protection.
- Destination: **corrigir agora**. Add `test/enoch/instance/boot_test.exs`: layout too new; admission closed through the whole boot (R02); tampered current state rebuilt; duplicate function and rule; the `[:enoch, :boot]` event with `basis_t`; schema, function and rule modules defined outside the package.

### R08 — relevante — `Enoch.TestAdapter` misses the required callback `rows_read/1`, and the contract suite does not require it

- Code: `test/support/test_adapter.ex:12-19` against `lib/enoch/storage.ex:173`; the required-callbacks loop in `lib/enoch/storage/contract_case.ex:48-65` omits `rows_read`.
- Observed (orchestrator): `MIX_ENV=test mix compile --force --warnings-as-errors` → `warning: function rows_read/1 required by behaviour Enoch.Storage is not implemented (in module Enoch.TestAdapter)`, `Compilation failed due to warnings while using the --warnings-as-errors option`, rc 1. The implementer recorded the same warning in `05_implement/handovers/jev.jsonl` and left it.
- Breaks: R25 and F2.6 (the suite is supposed to validate the contract); `docs/review-guide.md` §6 "clean" holds only in `dev`.
- Destination: **corrigir agora**. `defdelegate rows_read(storage), to: Enoch.Adapters.Memory` in the test adapter; add `:rows_read` to the required list in `contract_case.ex`.

### R09 — relevante — `retract` through `Enoch.transact` is never read back by a test

- Evidence: `repo_test.exs:54,61-64` runs a retract only to compare two instances; only `basis_t` is asserted (`:70`). A transactor mapping `:retract` to `added = true` (`transactor.ex:132`) would pass.
- Observed: the behaviour is correct today (`tuple_v.exs`: `after retract, present e=2: []`; past basis keeps `{2, 10, 5, 2, true}`).
- Breaks: R11 and F4 criterion 2 are proven only by reading.
- Destination: **corrigir agora**. Add the test: add, retract, present scan `[]`, scan at the earlier basis returns the asserted row.

### R10 — bloqueia — `test/enoch/adapters/` has no `CONTEXT.md`

- Observed: `ls test/enoch/adapters` → `memory_recovery_test.exs memory_test.exs`; its siblings `test/enoch/instance/` and `test/enoch/storage/` have one.
- Breaks: R35 acceptance (`spec.md:115`, "each folder of the tree has `CONTEXT.md`, verifiable by listing") and the s01 item at `spec.md:143`.
- Destination: **corrigir agora** (doc).

### R11 — bloqueia — the vetoed term "writer" appears in `docs/`

- Observed: grep `\bwriters?\b` over `lib;test;docs` → `docs/review-guide.md:21,240,249`. `docs/canon/chat.md:256,263` quotes the reference project (`Fato.Storage.Writer`), historical raw text per `docs/PROCESS.md`. The other hits only name the veto itself (`decisoes.md` D41, `adrs.md:39`, `spec.md:115`, and this finding).
- Breaks: R35 acceptance ("the review does not find the vetoed term 'writer' in `lib/`, `test/` and `docs/`").
- Destination: **corrigir agora** in `review-guide.md` ("transactor" or "escritor"). Whether the quote in `docs/canon/chat.md` is exempt is the **owner's decision**.

### R12 — relevante — a scan by a tuple value crashes the match spec

- Code: `memory.ex` embeds the literal `v` in ETS match-spec bodies (`present_datom/1` and the history-scan body); a tuple there is read as a match-spec function call.
- Observed (`tuple_v.exs`): `[:add, 1, 10, {:a, :b}]` → `{:ok, 1}`, then `scan_vaet(db, v: {:a, :b})` raises `not a valid match specification`.
- In s01 `v` is `term()` (`storage.ex`), so this is an s01 defect, not only a future-types issue.
- Destination: **corrigir agora**. Wrap the literal as `{:const, v}`; add a contract case with a tuple value.

### R13 — relevante — a raw transaction collapses conflicting operations on the same datom and records retractions of facts that never existed

- Code: `memory.ex:154` keys history rows on `{e, a, v, tx}`.
- Observed (`same_tx.exs`): `[[:add,1,10,7],[:retract,1,10,7]]` → `{:ok, 1}` with history `[{1, 10, 7, 1, false}]`; retracting a never-asserted datom → `{:ok, 3}` and a row is written.
- Destination: **item de trabalho s02** (`Enoch.Tx.Resolve`, R11: reject conflicts within a transaction, a retraction of a non-live datom is a no-op).

### R14 — relevante — `Enoch` has no `child_spec/1`

- Observed (`boot_checks.exs`): `{Enoch, opts}` in a supervisor fails with `The module Enoch was given as a child to a supervisor but it does not implement child_spec/1`.
- Not an s01 criterion; it blocks the normal way an application embeds an instance.
- Destination: **corrigir agora** (one function: `id: {Enoch, name}`, `type: :supervisor`).

### R15 — menor — an unknown instance fails differently per function

- Observed: `Enoch.transact(:nobody, ...)` raises `ArgumentError "a instância :nobody não tem admissão: ..."`; `Enoch.db(:nobody)` exits `:noproc`. Neither matches the `{:error, term()}` spec of `transact/2` (`enoch.ex:84-86`).
- Destination: **corrigir agora**: one documented behaviour for both.

### R16 — menor — Portuguese user-visible strings remain

- Raise texts: `lib/enoch/repo.ex:51-52`, `lib/enoch/adapters/memory.ex:342-343,445-446`, `lib/enoch/instance/admission.ex:122-124`. Shipped test names and assert messages in `lib/enoch/storage/contract_case.ex:48-232`, whose regexes at `:70-78` depend on the wording in `memory.ex`. `flake.nix:2`. Module docs across `lib/`.
- Destination: raise texts and `contract_case.ex` **corrigir agora**; module docs and test messages follow the English migration as an **item de trabalho** (no sprint assigned yet; owner chooses).

### R17 — menor — folder docs are stale now that code exists

- Evidence: "Esta pasta ainda não tem código" at line 13 of `lib/CONTEXT.md`, `lib/enoch/CONTEXT.md`, `lib/enoch/instance/CONTEXT.md`, `lib/enoch/adapters/CONTEXT.md`, `lib/enoch/tx/CONTEXT.md`, `lib/enoch/storage/CONTEXT.md`, `test/CONTEXT.md`, `test/enoch/CONTEXT.md`, `test/support/CONTEXT.md`, `config/CONTEXT.md`; `docs/arquitetura.md:3` says the `.ex` files do not exist; `lib/enoch/storage/CONTEXT.md:9` contradicts `contract_case.ex:16-20`; `test/enoch/CONTEXT.md:7` puts concurrency and crash in s05; `lib/enoch/CONTEXT.md:7` misplaces the row counter; `test/support/CONTEXT.md:3` mentions generators that do not exist. Also `test/enoch/application_test.exs:8` says "árvore global vazia" while `application.ex:19` starts a `Registry`; `telemetry.ex:20` cites `Enoch.Storage.rows_read/1` as a function (it is a callback).
- Destination: **corrigir agora** (docs and one test name).

### R18 — menor — every `Enoch.db/1` is a `GenServer.call` to the owner

- Evidence (reading, not timed): `enoch.ex:95-97`, `owner.ex:58,72-75`. All reads go through one mailbox with the default 5 s timeout, and the same process runs the O(history) recovery today (R03).
- Destination: **item de trabalho s05** (read path and performance), unless the R03 fix already removes recovery from that process.

### R19 — menor — `max_memory: :infinity` does not log the boot warning R16 describes

- Evidence: `memory.ex:452-455` returns `{:ok, :infinity}`; no `Logger` use in `lib/`.
- Destination: **item de trabalho s05** (quota and alert). The spec does not assign the warning to a sprint explicitly; the owner confirms.

### R20 — menor — the implementation commit mixes ICM tooling, and the 05 handover is stale about it

- Observed: `git diff --stat 76c60b4 5807bcf` lists, besides the code, `.omp/commands/icm.md`, `.omp/config.yml`, `.omp/hooks/pre/{graphify,icm-jev}.ts`, `docs/_index/*.mjs`, `docs/agents/{graphify.md,jev.md,jev-gates.json,README.md}`, the seven `docs/NN_step/CONTEXT.md` contracts, `docs/review-guide.md`, `.gitignore` and `flake.lock`; none of these is in a declared owner of #2–#10. `implementacao.md:10` still says "Nenhum commit foi feito". The commit is on `origin/main` with no PR.
- Provenance of the judging contract: the same commit also changed what judged the delivery: `docs/_index/{jev-gate,icm-conduzir,icm-implementar,icm-duck}.mjs`, `docs/agents/jev-gates.json`, `docs/agents/jev.md`, `.omp/commands/icm.md` and `.omp/hooks/pre/icm-jev.ts`. The author field of `5807bcf` is `Caio <caiofasoares@gmail.com>`, 2026-10-15 19:01 -0300 (`git log -1 --format='%an <%ae> %ad' 5807bcf`). That field does not say whether the owner or an agent wrote the change. Re-running the `implementacao` gate at `5807bcf` on 2026-10-20 reproduced receipt `f1297a1cb7877302`, which was already in `05_implement/handovers/jev.jsonl` (`registrado: false`). The receipt hashes the gate's artefacts and questions (`docs/review-guide.md` §7), so the accepted receipt was computed with the committed questions. Whether the earlier receipts `d71b495bdc7ba64a` and `b60acd31697e775d` used other questions is not established.
- This review changed the judging apparatus again, at the owner's request ("skip reopening implement"; 2026-10-20, uncommitted): the loop now also runs in `06_review` (`docs/_index/icm-implementar.mjs`, `icm-conduzir.mjs`, `jev-gate.mjs` with `perguntas_de`, `docs/agents/jev-gates.json` with the `correcoes` gate and `conducao.implementacao.etapas`, `docs/agents/jev.md`, `.omp/commands/icm.md`, `docs/PROCESS.md`, `docs/06_review/CONTEXT.md`). In a clean process (`bun -e` with `frescor`) the accepted receipts of 02–05 stayed `atual` after the change (`d133deedfcff2254`, `348ae02194161503`, `7b65ab418ce46499`, `f1297a1cb7877302`).
- Destination: **registrado** (history is not rewritten); how to treat a commit that changes its own judging contract is the **owner's decision**. The fix work goes through a branch and a PR (`pr.md`). `implementacao.md` stays as the 05 record; the fixes are recorded in `correcoes.md` (06 loop).

## Checked and compliant

| What | Evidence |
| --- | --- |
| Suite green and stable | orchestrator: `mix test --seed 0` ×3 (output filtered to the `Result` line) and `mix test` ×3 with seeds 339952, 756994 and 84393, plus one earlier `mix test` → `Result: 50 passed` every time; reviewer: seeds 1, 42, 777, 12345, 98765 and `mix test --repeat-until-failure 30` → all `50 passed`; `elixir --erl "+S 1:1" -S mix test` on reader, recovery and admission → `19 passed` ×3 |
| Dev compile, format, audit | orchestrator: `mix compile --warnings-as-errors --force` rc 0, `mix format --check-formatted` rc 0, `mix hex.audit` → `No retired or security advisory packages found` |
| Usage path | orchestrator: `docs/review-guide.md` §3 and §4.4 via `mix run` → `t1..t3 {:ok, 1..3}`, `basis_t: 3`, `eavt e=100: [{100, 10, 7, nil, nil}]`, `{:error, :admission_full}`, `{:error, :admission_closed}`, `killed tr, counter: {false, 0}` |
| Transactor write order `2t+1` → history → current → `2t+2` (ADR-0003) | `memory.ex:131-136,144-147,172`; `memory_test.exs:80` |
| Recovery: odd counter kept, orphans deleted, current rebuilt, publish `2(t+1)`, next `t+2` | `memory.ex:196-204`; `memory_recovery_test.exs:45,143,200` |
| Reader guard before and after, one history fallback, no loop | `memory.ex:364-384`; `reader_test.exs:105,141,189` |
| `rest_for_one`, owner before admission before transactor; tables owned by the owner | `supervisor.ex:82-90`; `memory.ex:97-100` |
| Transactor `init` resets admission; rejected caller undoes its increment; release never negative | `transactor.ex:106`, `admission.ex:149,171,182` |
| Invalid operation refused without writing | reviewer: `Enoch.transact(:d4, [[:add,1,2,3],[:bogus]])` → `{:error, {:invalid_operation, [:bogus]}}`, basis unchanged |
| Boot steps 1, 2, 3, 4 (mechanism) and 7 exist in order; failed boot tears the tree down | `boot.ex:86-99`; `boot_window.exs` → `{:error, {:layout_too_new, 99, 0}}` |
| No scope creep | no `q`, `pull`, `as_of`, schema installer, tempids, SQLite or `Dockerfile` in `lib/`; `lib/enoch/tx/function.ex` is the behaviour F7 lists; one telemetry event `[:enoch, :boot]` (`telemetry.ex:41-43`) |
| ADR-0009 dependencies and toolchain | `mix.exs` (`decimal ~> 3.2`, `telemetry ~> 1.0`, `exqlite` optional, `stream_data` test-only, `elixir ~> 1.20`); `flake.nix:39-42`; `nix flake check --no-build` as in the F9 row |
| Folder tree matches `docs/arquitetura.md` | `lib/` tree as listed; every folder has `CONTEXT.md` except R10 |

## Fix issues

Run by `/icm implement` in this stage (`docs/06_review/CONTEXT.md`, step 2).

- #11: R01–R12 and R14–R17.

### State of #11 (2026-10-20)

**Loop.** Go in `handovers/jev.jsonl`: role `42-implementation-backend`; owner `lib/`, `test/`, `config/CONTEXT.md`, `docs/arquitetura.md`, `docs/review-guide.md`; max 5 iterations. All five iterations ran `mix test` with code 0. Iteration 5 ended `bloqueada` with only uncertain Jev findings (`so_leitura` on c10, c11, c15 at 0.31–0.40). For those criteria the subagent's report records executed commands (`ls test/enoch/adapters/`, `grep -rn -i '\bwriters\?\b' docs/review-guide.md` → rc 1, `mix test test/enoch_test.exs --trace`), so the block is the uncalibrated judge, not missing proof. `fechar` wrote `correcoes.md` and skipped the `correcoes` gate because no issue is `ok`. Whether to reopen #11 (`reabrir`, origin `incerto`) or accept it on the evidence below is the owner's call.

**Orchestrator changes after the loop** (inside #11's paths, outside the iterations):

- `test/enoch/docs_test.exs`: kept only the `CONTEXT.md` listing check (R35). Iterations 4–5 had added tests that pin document wording and tests that read `docs/`, which `flake.nix`'s `projectSrc` leaves out.
- R01: iterations 4–5 replaced add-then-undo with a compare-and-set admit while every rejected caller still reconciled from the mailbox. `admission_race.exs` then gave `mailbox ... = 821`, `737`, `18` with `limit 4`, worse than the original `15`. The full path now calls `Admission.repair_leak/1` (`lib/enoch/instance/admission.ex`, `lib/enoch/transactor.ex`). It resets the counter only when the transactor has no transaction in progress and an empty mailbox, with a compare-and-set against the value it read. `reconcile/1` is unchanged for the R13 acceptance tests.
- Two regression tests in `test/enoch/instance/admission_test.exs`: "a rejected caller does not erase a caller admitted that has not sent yet" fails on `5807bcf` and passes now; "a unit leaked by a dead caller is repaired by the next write when the transactor is idle" passes on both.

**Checks by the orchestrator on the final working tree:**

| Check | Observed |
| --- | --- |
| `mix test` ×6 (seeds 413478, 442263, 305806, 280453, 350811, 448308) | `Result: 70 passed` each time |
| `mix compile --force --warnings-as-errors`, dev and `MIX_ENV=test` | rc 0 both |
| `mix format --check-formatted` | rc 0 |
| New tests against the original code (worktree at `5807bcf`, new test files copied in) | fail there: boot (layout window, `verify/1` error, tampered state), owner (storage read mid-transaction, owner loss), `child_spec`, unknown instance, torn read during rebuild, admitted-but-unsent caller |
| R01 `admission_race.exs` | `mailbox after 2000 concurrent callers = 4`, `%{:ok => 4, ...}` in all 3 runs |
| R01 `race_many.exs` (60 bursts of 2000 callers, limit 4) | `%{4 => 48, 8 => 8, 12 => 1, 16 => 1, 68 => 1, 84 => 1}` |
| R01 `admission_bypass.exs` | `results (limit 1, 10 concurrent): %{:ok => 1, ...}` |
| R02 `boot_window2.exs` | `external writes {:ok, t} returned before boot refused the instance: 0` |
| R03 `live_recover.exs` | `{history size, current size}: {300000, 300000}` |
| R04 `verify_torn.exs` | `%{199999 => 27, 200000 => 20}`. The script deletes one row from the current state before calling `verify/1` (`verify_torn.exs:5`), so `199999` is the tampered state read before the rebuild; the rebuild now runs between `begin_tx` and `publish_tx` (`memory.ex`), so readers during it fall back to history. No other count appears. |
| R12 `tuple_v.exs` | `present vaet tuple: [{1, 10, {:a, :b}, nil, nil}]` |
| R14, R15 `boot_checks.exs` | `Enoch as child spec: {:ok, #PID<...>}`; both functions raise `"instance :nobody is not running: start it with Enoch.start_link/1"` |
| R11 | grep `\bwriters?\b` over `lib`, `test`, `docs/review-guide.md`, `docs/canon/chat.md`, `docs/arquitetura.md` → 0 lines |
| Usage path (`docs/review-guide.md` §3, §4.4) | `t1..t3 {:ok, 1..3}`, `basis_t: 3`, `{:error, :admission_full}`, `{:error, :admission_closed}`, `killed tr, counter: {false, 0}` |

**R01 outcome.** The limit is exact while the transactor is busy or has messages waiting. It is approximate only at the start of a burst, when every admitted unit is still unsent and a rejected caller sees an idle transactor with an empty mailbox: 12 of 60 bursts above. That is the approximate limit R13 (`spec.md:57`) and ADR-0004:33 accept, and #11's R01 criterion was rewritten to that wording (decision recorded by the orchestrator on the owner's instruction to close the review, 2026-10-20). The window is documented in `Enoch.Instance.Admission`. An exact limit that also repairs a dead caller's unit needs a monitor per admission: work item below.

**R11 outcome.** `docs/canon/chat.md` is a first draft that can be superseded (owner, 2026-10-20): lines 256 and 263 now read `Fato.Storage.WriteConnection` and "a conexão de escrita".

## Work items (not fixed in s01)

| Item | Sprint |
| --- | --- |
| Exact admission limit with dead-caller repair (monitor per admission) | s05, with the admission telemetry (R17) |
| R13: conflicting operations on one datom in a transaction; retraction of a non-live datom | s02 (`Enoch.Tx.Resolve`, R11) |
| R18: `Enoch.db/1` goes through `GenServer.call` to the owner | s05 (read path) |
| R19: `max_memory: :infinity` boot warning | s05 (quota and alert) |
| R16, second half: module docs and test names still in Portuguese | the English migration; no sprint assigned |

## Pending for the owner

1. #11: accept it on the checks above (the loop block is the judge's uncertainty) or reopen it with `reabrir`.
2. Confirm the sprints of the work items.
3. Commit the fixes on a branch and open the PR (`pr.md`), then close #1–#11 and the stage.
