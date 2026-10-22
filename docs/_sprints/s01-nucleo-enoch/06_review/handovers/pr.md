---
sprint: s01-nucleo-enoch
step: 06_review
---

# PR — s01-nucleo-enoch

> **State:** the fixes are in the working tree, uncommitted. The s01 code (`5807bcf`) was pushed straight to `origin/main`, so the PR carries only the review fixes: a branch from `main` with the working tree, against `main` on `CaioFaSoares/EnochDB`. Committing, pushing and opening the PR are the owner's acts; the body below is that PR's description.

## Scope

- Base already on `main` (`5807bcf`): the storage contract `Enoch.Storage` and its contract suite, the `Memory` adapter, the instance (`Enoch.start_link`, `transact`, `db`), admission, recovery after a transactor crash, the boot steps 1, 2, 3 and 7 plus the step 4 mechanism, the `[:enoch, :boot]` event, `use Enoch.Repo`, and the flake. Objective and out-of-scope list: [`../../CONTEXT.md`](../../CONTEXT.md).
- This PR (issue #11): the **corrigir agora** findings of [`revisao.md`](revisao.md) (R01–R12, R14–R17) — boot with admission closed until step 7 and the transactor started after steps 1–2, recovery only in the transactor's start, rebuild bracketed by the counter, `verify/1` errors stop the boot, owner loss stops the instance, admission without mailbox reconciliation on the hot path, tuple values in scans, `child_spec/1`, one error for an unknown instance, English raise texts, folder docs, and the tests for each.
- Also in the working tree: the ICM change that lets the loop run in `06_review` (R20 in `revisao.md`), and `docs/canon/chat.md` without the vetoed term.

## Related items

- #11 (fixes). #2–#10 (F1–F9), mapped in [`../../04_tickets/handovers/tickets.md`](../../04_tickets/handovers/tickets.md). #1 (folder tree): R10 is fixed by #11.
- Work items left out are listed in `revisao.md`, "Work items".

## Decisions affected

- ADR-0002, ADR-0003, ADR-0010: R03, R04, R06 brought back in line.
- ADR-0004: R01 keeps the approximate limit that ADR-0004:33 and R13 accept; the window is documented in `Enoch.Instance.Admission`.
- ADR-0008: R02 and R05 brought back in line.
- No ADR text changes.

## Verification executed by the orchestrator (2026-10-20, working tree)

| Command | Observed |
| --- | --- |
| `mix test` ×6 (seeds 413478, 442263, 305806, 280453, 350811, 448308) | `Result: 70 passed` each time |
| `mix compile --force --warnings-as-errors` (dev) and `MIX_ENV=test mix compile --force --warnings-as-errors` | rc 0 both |
| `mix format --check-formatted` | rc 0 |
| `mix hex.audit` | `No retired or security advisory packages found` |
| new tests run against `5807bcf` (worktree) | fail there, pass on the working tree (list in `revisao.md`) |
| `mix run /tmp/enochrev/{admission_race,race_many,admission_bypass,boot_window2,live_recover,verify_torn,tuple_v,boot_checks}.exs` | outputs in `revisao.md`, "State of #11" |
| `mix run /tmp/enoch_smoke.exs` (review-guide §3, §4.4) | `t1..t3 {:ok, 1..3}`, `basis_t: 3`, `{:error, :admission_full}`, `{:error, :admission_closed}`, `killed tr, counter: {false, 0}`, `after restart: {:ok, 3}` |

Not run: `nix run .#test`, `nix run .#estado` and a full `nix flake check`. Nix reads the git tree, and the new test files are untracked until the commit; run them after committing.
