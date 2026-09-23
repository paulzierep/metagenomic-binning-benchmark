# Changelog

All notable changes to the metagenomic-binning-benchmark automation &
documentation.

## 2026-09-23 — Reproducible dataset preservation staging

- Added `docs/10-data-preservation.md` with the Zenodo release scope, owner/token
  prerequisites, licensing and provenance checklist, and post-upload DOI
  verification steps.
- Added `scripts/make_release_manifest.py` to stream SHA-256 hashes and sizes
  into a deterministic manifest outside the dataset directory; the small
  derived dataset has a local manifest ready for review. No upload is claimed
  until an approved Zenodo deposit is verified.

## 2026-09-23 — Issues can now be closed when addressed (`issue-closer`)

### Added — deterministic issue closing, zero LLM tokens

New `bin/issue-closer.sh` (invoked by `meta-watchdog.sh` on every 10-min
tick, alongside the existing C8 issue triage) closes GitHub issues that have
been explicitly marked as addressed:

- **Contract:** write a one-line closing reason to
  `/vol/data/benchmark/meta/.issues_done/<number>`. On the next tick the
  closer verifies the issue is open, closes it via `gh issue close` with the
  recorded reason as the closing comment, re-verifies the closed state (does
  not trust the close call's exit code alone), records it in
  `status/meta/issues_closed.tsv`, and advances the `updatedAt` marker so
  meta-watchdog never re-escalates a closed issue.
- **Safety:** per-run cap (default 5 closes), idempotent markers, no force
  close, non-numeric markers purged, and a per-script `flock`. Closing is a
  controlled shell action — the LLM never closes issues directly, it only
  writes markers after work is verified done.
- Issues #3 (comebin "stuck" — verified healthy), #4 (agents often broken —
  root cause fixed) and #5 (comebin fork — rebased to v1.1.0) were closed
  with this mechanism; #1 (idea inbox) and #2 (small dataset, still active)
  stay open.

## 2026-09-23 — Status truthfulness, 2-min heartbeat, model column

### Fixed — status no longer lies on a stale agent note

The GitHub status mirrored the agent's `.activity` note verbatim, so a note
written early (e.g. "epoch ~37/200" from 16:10 UTC) could keep displaying for
hours while the real training log advanced (epoch 110+). The headline numbers
are now **derived from the actual files**:

- The **live epoch / loss / top1 accuracy** are parsed from the newest
  `runs/<run>/comebin_out/<stage>/training.log` (run root from
  `.active_run`, fallback glob) and shown in the README banner,
  `status/current.md` and `status/status.log` (`epoch=`/`loss=`/`acc=`
  columns).
- The agent's `.activity` note is still shown, but **age-tagged**
  ("Agent note · N min old") so it can never masquerade as ground truth.
- The **"Benchmark runs — performance" table** in the README now gets its
  Status cell refreshed from the live training log on every significant
  change, instead of staying frozen at "⏳ env finishing, next step".

### Changed — heartbeat is every 2 min and commits only real changes

- `status-heartbeat.sh` cron cadence `*/10` → **`*/2`** (GitHub rate limits
  are nowhere near, and the heartbeat is pure shell — zero LLM tokens).
- **Skip-if-unchanged**: generated files (README, `current.md`, `status.log`)
  are only rewritten and committed when the *meaningful* status changed
  (state / note text / transcript growth / live epoch / model), so idle
  periods produce no commit spam.
- **Model column**: `status/status.log` rows and `current.md` now record the
  model actually used on the last turn (parsed from the transcript's
  `> <agent> · <model>` line, fallback `model.json`), so quota-driven
  rotation to free models is visible.

### Ops

- `meta-watchdog.sh` C1 cron template updated to the `*/2` heartbeat cadence
  (its parity check C5 is already compatible with skip-if-unchanged).

## 2026-09-23 — Ops overhaul: persistent agent, GitHub logging, supervisor

### Fixed — "agent is always stopped" (watchdog redesign)

**Root cause:** `opencode run --auto` is a **single-turn** command in OpenCode
v2 — it sends the prompt, the agent completes *one* assistant turn ("Turn
complete"), prints it, and exits with rc=0. The old `agent-watchdog.sh`
launched one run per cron tick and waited ~20 min for the heartbeat to go
stale before relaunching, so the agent effectively never got more than one
turn at a time. On top of that, every launch burned one of 6 slots in the 6 h
crash-loop window; after 6 one-turn runs the watchdog went into
"rate-limited" and refused to restart for hours (this blocked the agent from
~17:35 to ~21:30 UTC).

**Fix (`bin/agent-watchdog.sh`):** the watchdog now drives a **persistent
driver loop** — each cron invocation that finds the agent idle starts a driver
that calls `opencode run --auto --session <id>` repeatedly, one turn per call
on the *same* session (conversation context carries over), until:

- `TASK_COMPLETE` appears,
- the agent crashes / runs out of tokens (cron relaunches),
- a hard budget is hit (`MAX_TURNS=200` or 8 h runtime).

Supporting behavior:

- **One driver at a time** via `flock /tmp/agent-watchdog.lock`; the 5 min
  cron tick simply skips while a driver is alive.
- **Idle backoff** — if the agent ends a turn saying it is waiting ("nothing
  to do", "waiting for training"), the next turn waits 10 min instead of 30 s,
  so it does not burn tokens hot-looping during long waits.
- **Crash-guard reset** — a driver that survives ≥ 2 turns clears the
  .watchdog_attempts markers, so healthy restarts are never rate-limited by
  stale history.
- **Model rotation** on quota/429/context-exhaustion (falls back through the
  4 free models; new default model cycle only after repeated failures).

### Added — full agent logging pushed to GitHub

`bin/status-heartbeat.sh` (cron */2) now mirrors **everything the agent did**
into the repo, in addition to the existing banner / current.md / status.log /
agent-activity.log:

| Artifact (in repo `status/`) | Contents |
|---|---|
| `agent-run.log` | Full transcript of every `opencode run`: prompts, every `$` command, tool output, "Turn complete" summaries |
| `watchdog.log` | Every restarter decision (idle detection, model rotation, rate limits) |
| `supervisor-run.log` | Output of on-demand LLM supervisor escalations |
| `meta/` | Supervisor health checks (`checks.tsv`, `last.txt`, `issues.tsv`) |

`status.log` timeline rows now include transcript/watchdog byte sizes, and
`current.md` gained an "Agent transcript" row.

### Added — supervisor agent ("meta-watchdog", watches the watchers)

New `bin/meta-watchdog.sh` (cron at `3,13,23,33,43,53`, i.e. offset 10 min)
runs deterministic health checks every 10 minutes, auto-fixes the cheap
breakages, and escalates to an on-demand LLM supervisor only when needed:

| Check | Watches |
|---|---|
| C1 | cron jobs installed (all 4, reinstalls if missing) |
| C2 | opencode background service alive (restarts if dead) |
| C3 | agent driver / run process / heartbeat / transcript freshness (relaunches driver) |
| C4 | watchdog crash-guard not deadlocked (clears stale markers + relaunches) |
| C5 | GitHub push freshness (re-runs status-heartbeat) |
| C6 | benchmark run alive & log advancing (invokes benchmark-watchdog if hung) |
| C7 | disk free on /vol/data |
| C8 | **GitHub issues** — new/updated open issues → escalation |
| C9 | meta artifacts actually committed and present at the remote SHA |

Escalation is rate-limited to 3 LLM calls per 6 h (cost guard); the supervisor
agent gets a full diagnostics bundle, fixes what it can, appends to
`logs/supervisor-actions.log`, and pushes — all recorded in
`status/supervisor-run.log`.

### Operations

- Cleared the stale `.watchdog_attempts` markers left over from the
  single-turn era (they were blocking restarts until ~21:30 UTC).
- Baseline unmodified COMEBin run: training resumed/verified healthy
  (epoch 99+/200 reached, `main.py` at ~3100% CPU, logs advancing every few
  seconds).

### Supervisor hardening (2026-09-23 19:03 UTC)

- Scoped agent liveness to the primary session/driver lock so a supervisor's
  `opencode run` can no longer masquerade as the coding agent.
- Issue `updatedAt` markers now advance only after successful triage. Comment
  IDs are compared before/after so the automation's own response does not create
  an endless self-trigger, while failed/over-budget updates remain retryable.
- Replaced process-name and recent-local-commit heuristics with OpenCode's
  documented service/API checks, actual remote-SHA verification, source/installed
  checksums, owner-scoped heartbeat logic, and shared repository locking
  (`git commit --only`). LLM and per-turn agent calls have hard timeouts and
  children no longer inherit watchdog lock FDs.
- Benchmark restarts preserve explicit mode/source/data, verify PID start +
  PGID (including safe orphan groups), use a stable restart budget, hand off
  `.active_run` atomically, and kill only the registered process group (no broad
  `pkill -f`). Evaluation and small/fix runners share the launch guard.
- Small-test runner now refuses overlap/overwrite, supports baseline or v1.1.0
  source, uses small-data CPU/seed parameters, and records the promised resource
  timeline. Issue #2's medium stage is documented (3,000 contigs, 5 GB cap) but
  correctly remains gated on the end-to-end small run.