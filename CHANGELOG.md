# Changelog

All notable changes to the metagenomic-binning-benchmark automation &
documentation.

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

`bin/status-heartbeat.sh` (cron */10) now mirrors **everything the agent did**
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
runs 8 deterministic health checks every 10 minutes, auto-fixes the cheap
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