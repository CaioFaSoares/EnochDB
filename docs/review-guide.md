# Review guide — what EnochDB does today

Manual testing guide for the `s01` slice of the `e01` epic. The sections below were executed with
Elixir 1.20.4 / OTP 29.1.1: §3 and §4 were re-executed on 2026-10-20, after the review fixes of issue #11, and
the Nix commands in §2 were executed on 2026-10-15 with Determinate Nix 3.22.5 and not re-run. The "expected"
blocks are the observed output, not a description of it. Commands run from the repository root.

Scope note: this guide covers the code and the tooling. The sprint artefacts (spec, tickets, handovers) live in
`docs/_sprints/s01-nucleo-enoch/`, and the design decisions in the ADRs under `docs/adr/`. Those are still
written in Portuguese: the migration to English is in progress, and legacy documents are deliberately untouched.

## 1. What exists today

One Elixir package, `enoch`, with a single adapter and no query layer yet:

- `Enoch.start_link/1` — starts one instance: its own supervision tree plus a seven-step boot.
- `Enoch.transact/2` — a raw transaction: `[:add, e, a, v]` and `[:retract, e, a, v]`.
- `Enoch.db/1` — the database as an immutable value carrying the base.
- `Enoch.Adapters.Memory` — two ETS tables (insert-only history and current state) with a base counter.
- `Enoch.Storage` — the adapter behaviour, plus `Enoch.Storage.ContractCase`, a contract suite an external adapter can reuse.
- `use Enoch.Repo` — a thin module that delegates to the functional core by instance name.
- Bounded admission, transactor recovery after a crash, and one telemetry event on boot.
- `Enoch.child_spec/1` — the instance as a `{Enoch, opts}` child of an application supervisor.

Not built yet: the Datalog evaluator (`q`), `pull`, `as_of`, `:history`, the schema DSL and installer,
`:decimal` and the other types, the SQLite adapter, data migrations, and the example application. Those are
sprints `s02` to `s05`.

## 2. Get it running

```bash
mix deps.get          # deps are already vendored in deps/; this is a no-op check
mix test              # 70 tests
```

Expected:

```
Result: 70 passed
```

Through Nix instead (pinned toolchain, `beam.packages.erlang_29.elixir_1_20`):

```bash
nix develop                        # dev shell with elixir, hex, rebar3, make, git
nix run .#test                     # builds the derivation and runs the suite
nix run .#estado                   # derived state of epics, sprints and backlog
nix flake check                    # devShell + both apps + checks.<system>.test
```

Expected: `nix run .#test` prints `Result: 71 passed`; `nix flake check` ends with
`✅ checks.aarch64-darwin.test (previously built)` and exit 0.

> **Nix needs the files visible to git.** Nix reads the git tree, so an untracked `flake.nix` or untracked
> `lib/` makes all three commands fail with `Path 'flake.nix' ... is not tracked by Git`. Fix:
> `git add -N .formatter.exs config lib mix.exs mix.lock test flake.nix` (intent-to-add, no commit) — or commit.
> This guide was validated with those intent-to-add entries in place, plus the `flake.lock` that Nix created.

## 3. One-minute smoke test

Paste into `iex -S mix`:

```elixir
{:ok, _} = Enoch.start_link(name: :demo, adapter: Enoch.Adapters.Memory, storage_opts: [max_memory: :infinity])
{:ok, 1} = Enoch.transact(:demo, [[:add, 100, 10, 7]])
{:ok, 2} = Enoch.transact(:demo, [[:retract, 100, 10, 7]])
{:ok, 3} = Enoch.transact(:demo, [[:add, 100, 10, 7]])
Enoch.DB.basis_t(Enoch.db(:demo))
Enoch.Adapters.Memory.scan_eavt(Enoch.db(:demo), e: 100)
```

Expected (observed):

```
basis_t: 3
scan_eavt e: 100: [{100, 10, 7, nil, nil}]
```

Read that carefully, because it is the core promise of the model: three transactions were applied, `basis_t`
counts all three, and the current state holds exactly one live datom — the third transaction re-asserted a fact
that the second had retracted. Nothing was updated in place; the history kept every step.

## 4. Feature-by-feature manual tests

### 4.1 Boot, supervision tree and the boot event

```elixir
defmodule Guide.Telemetry do
  def handle(event, measurements, metadata, pid), do: send(pid, {:boot, event, measurements, metadata})
end

:telemetry.attach("guide", Enoch.Telemetry.boot_event(), &Guide.Telemetry.handle/4, self())
{:ok, _} = Enoch.start_link(name: :demo, adapter: Enoch.Adapters.Memory, storage_opts: [max_memory: :infinity])
Supervisor.which_children(Enoch.Instance.Supervisor.name(:demo)) |> Enum.map(&elem(&1, 0))
receive do {:boot, e, m, md} -> {e, m, md} after 500 -> :not_received end
```

Expected:

```
children ids: [Enoch.Transactor, Enoch.Instance.Admission, Enoch.Instance.Owner]
telemetry: {[:enoch, :boot], %{basis_t: 0}, %{instance: :demo}}
```

The owner of the tables is `Enoch.Instance.Owner`, so the tables outlive both the admission and the transactor.
The admission is born closed with the tree and only the boot's step 7 opens it; the transactor itself is started
by step 3, after the layout check and the current-state check. The boot event is the seventh step and carries the
base.

### 4.2 The four index scans and the rows-read counter

Continuing with the instance from §3:

```elixir
db = Enoch.db(:demo)
Enoch.Adapters.Memory.scan_eavt(db, e: 100)
Enoch.Adapters.Memory.scan_aevt(db, a: 10)
Enoch.Adapters.Memory.scan_avet(db, a: 10, min_v: 5, max_v: 8)
Enoch.Adapters.Memory.scan_vaet(db, v: 7)
Enoch.Adapters.Memory.rows_read(Enoch.Instance.Owner.storage(Enoch.Instance.Supervisor.owner(:demo)))
```

Expected:

```
scan_eavt e: 100: [{100, 10, 7, nil, nil}]
scan_aevt a: 10: [{100, 10, 7, nil, nil}]
scan_avet a: 10, 5..8: [{100, 10, 7, nil, nil}]
scan_vaet v: 7: [{100, 10, 7, nil, nil}]
rows read counter: 5
```

The datom shape is `{e, a, v, tx, added}`; the first three fields are the fact, and `tx`/`added` are `nil` in the
current-state index because it only holds live datoms. `rows_read/1` is the deterministic metric behind the
"the present does not pay for the history" criterion. The counter is cumulative since `open/1`, so the total is 5
here — the `scan_eavt` of §3 plus the four scans above; on a fresh instance the same four scans show 4.

### 4.3 Two instances are independent

```elixir
{:ok, _} = Enoch.start_link(name: :other, adapter: Enoch.Adapters.Memory, storage_opts: [max_memory: :infinity])
{Enoch.DB.basis_t(Enoch.db(:other)), Enoch.Adapters.Memory.scan_eavt(Enoch.db(:other), e: 100)}
```

Expected:

```
other instance (basis_t, e: 100): {0, []}
```

### 4.4 Bounded admission

```elixir
{:ok, _} = Enoch.start_link(name: :tight, adapter: Enoch.Adapters.Memory, storage_opts: [max_memory: :infinity], admission: [limit: 1])
tr = GenServer.whereis(Enoch.Instance.Supervisor.transactor(:tight))
:sys.suspend(tr)                                        # hold one transaction in flight
task = Task.async(fn -> Enoch.transact(:tight, [[:add, 1, 10, 1]]) end)
Process.sleep(150)
Enoch.transact(:tight, [[:add, 2, 10, 2]])              # above the limit
Enoch.Instance.Admission.counter(:tight)
:sys.resume(tr)
Task.await(task)
Enoch.Instance.Admission.close(:tight)
Enoch.transact(:tight, [[:add, 3, 10, 3]])              # external write, admission closed
Enoch.Instance.Admission.open(:tight)
Enoch.transact(:tight, [[:add, 3, 10, 3]])
Process.exit(tr, :kill)
Process.sleep(300)
{Process.alive?(tr), Enoch.Instance.Admission.counter(:tight)}
```

Expected:

```
write above the limit: {:error, :admission_full}
admission counter: 1
the in-flight write: {:ok, 1}
external write, admission closed: {:error, :admission_closed}
after reopening: {:ok, 2}
old transactor alive?, admission counter: {false, 0}
```

The rejection happens before the message reaches the transactor's mailbox, and killing the transactor leaves the
admission counter at zero — the `init` of the new transactor resets it.

### 4.5 `max_memory` is mandatory

```elixir
Enoch.Adapters.Memory.open([])
Enoch.Adapters.Memory.open(max_memory: :zero)
Enoch.Adapters.Memory.open(max_memory: :infinity) |> elem(0)
Process.flag(:trap_exit, true)
Enoch.start_link(name: :nomax, adapter: Enoch.Adapters.Memory)
```

Expected:

```
Memory.open([]): {:error, {:missing_option, :max_memory}}
Memory.open(max_memory: :zero): {:error, {:invalid_option, {:max_memory, :zero}}}
Memory.open(max_memory: :infinity) status: :ok
start_link without max_memory (exits trapped): {:error,
 {:shutdown,
  {:failed_to_start_child, Enoch.Instance.Owner, {:missing_option, :max_memory}}}}
```

Note the OTP detail: `Enoch.start_link/1` is a `start_link`, so without trapping exits the failed child start
propagates to the caller as an EXIT. Either trap exits (as above) or use `start_supervised` in tests. The error
itself is explicit and names the missing option.

### 4.6 `use Enoch.Repo`

```elixir
defmodule DemoRepo do
  use Enoch.Repo
end

{:ok, _} = Enoch.start_link(name: DemoRepo, adapter: Enoch.Adapters.Memory, storage_opts: [max_memory: :infinity])
{:ok, 1} = DemoRepo.transact([[:add, 7, 10, 7]])
{Enoch.DB.basis_t(DemoRepo.db()), Enoch.DB.basis_t(Enoch.db(DemoRepo))}
```

Expected:

```
repo db vs functional db: {1, 1}
```

The repo is only a name: identical results through the module and through the functional API. Passing options to
the macro raises, with the message in English:

```
use Enoch.Repo with options: {:raised,
 "use Enoch.Repo accepts no options in this sprint, got: [quarantine: :yes]"}
```

### 4.7 Embedding the instance and an unknown instance

```elixir
{:ok, _app} =
  Supervisor.start_link(
    [{Enoch, [name: :embedded, adapter: Enoch.Adapters.Memory, storage_opts: [max_memory: :infinity]]}],
    strategy: :one_for_one
  )

{:ok, 1} = Enoch.transact(:embedded, [[:add, 1, 10, 7]])
Enoch.transact(:nobody, [[:add, 1, 10, 7]])
Enoch.db(:nobody)
```

Expected:

```
embedded instance: {:ok, 1}
transact(:nobody, ...): {:raised, ArgumentError, "instance :nobody is not running: start it with Enoch.start_link/1"}
db(:nobody): {:raised, ArgumentError, "instance :nobody is not running: start it with Enoch.start_link/1"}
```

`Enoch.child_spec/1` gives the instance the id `{Enoch, name}` and the type `:supervisor`, so `{Enoch, opts}` is a
normal child of an application supervisor. An instance that is not running fails the same way through both
functions — one documented `ArgumentError`, not a `GenServer.call` exit.

## 5. The suite, file by file

`mix test` runs 70 tests. To review one behaviour at a time:

| Command | What it proves |
| --- | --- |
| `mix test test/enoch/application_test.exs` | the OTP app starts with the global registry of instances |
| `mix test test/enoch/adapters/memory_test.exs` | `max_memory` is mandatory, two ETS tables plus the `:atomics` counter, the transactor order `2t+1 → history → current → 2t+2`, the history checked in the table itself, and a reader that never accepts a torn current scan during the step 2 rebuild |
| `mix test test/enoch/adapters/memory_recovery_test.exs` | recovery after a crash mid-write: orphan rows removed, current state rebuilt, counter published at `2(t+1)`, next transaction `t+2`, and the tables staying with the owner (no heir) |
| `mix test test/enoch/storage/contract_test.exs` | the contract suite, run against the `Memory` adapter (the same suite an external adapter reuses) |
| `mix test test/enoch/storage/external_adapter_test.exs` | the contract suite run from outside `lib/enoch/adapters` |
| `mix test test/enoch/storage/reader_test.exs` | the reader: current state only when the counter validates, fallback to history otherwise, concurrent read with continuous write, and the same rows read before and after N retractions |
| `mix test test/enoch/instance/admission_test.exs` | the limit, the closed and open states, the counter reset on transactor restart, the reconciliation with `message_queue_len`, and a burst of concurrent callers rejected with the mailbox full — the limit is the approximate one of R13 and ADR-0004:33, whose overshoot window is documented in the module |
| `mix test test/enoch/instance/boot_test.exs` | the seven-step boot: a newer layout, the admission closed through the boot, a tampered current state rebuilt, `verify/1` errors, duplicate function or rule names, the boot event, and modules from outside the package |
| `mix test test/enoch/instance/owner_test.exs` | reading the storage mid-transaction does not recover, and losing the owner stops the instance |
| `mix test test/enoch_test.exs` | `add` then `retract` read back through `Enoch.transact/2`, `{Enoch, opts}` under a supervisor, and the one failure for an unknown instance |
| `mix test test/enoch/repo_test.exs` | the repo delegation and the refusal of options |
| `mix test test/enoch/docs_test.exs` | every code and test folder has a `CONTEXT.md` (R35, checked by listing) |

Two of these are the ones worth reading closely, because they encode the hardest guarantees:
`memory_recovery_test.exs` for what happens when the single transactor dies mid-write, and `reader_test.exs` for why
a reader never accepts a torn read.

Per-file counts, observed: application 1, memory 10, recovery 6, contract 10, external adapter 10, reader 5,
admission 13, boot 6, owner 2, public API 3, repo 3, docs 1 — 70 in total.

## 6. Quality gates

```bash
mix compile --warnings-as-errors               # clean
MIX_ENV=test mix compile --warnings-as-errors  # clean: the test adapter implements the whole contract
mix format --check-formatted                   # exit 0
mix hex.audit                                  # No retired or security advisory packages found
```

## 7. The ICM and the judge

The work above was produced by the ICM in this repository, which is also testable:

```bash
sh docs/_index/estado.sh        # derived state (epics, sprints, backlog)
/icm status                     # stage, gate verdict and receipt, issues, next steps
```

Derived state observed on 2026-10-15: stages `01_grilling` to `04_tickets` closed, `05_implement` in progress
with all nine issues `ok`, gate `implementacao` verdict `revisar` and receipt `f1297a1cb7877302`. Re-run the
commands above for the state of today. At that time the four open findings were advisory (three `so_leitura` and
one global `alega_sem_provar`), and the judge is uncalibrated (`calibrado: false`), so its verdicts are leads,
not proof.

One caveat for anyone re-running the gates: the receipt is a hash over the gate's artefacts **and its
questions**, so re-running after the English migration produces a different receipt id than the recorded ones.

## 8. What is not there yet (do not go looking for it)

- `q`, `pull`, `as_of`, `:history` — the query layer is `s03`.
- Schema declaration, the installer, `:decimal` and the value types — `s02`.
- The SQLite adapter, layout version on disk, persistence across restarts — `s04`.
- Migrations, `max_memory` quota enforcement, the soft limit, the example application — `s05`.
- The `Dockerfile` — `s05`.
