# 05 — Agent restart & model switching (watchdog)

How the coding agent (OpenCode) that performs this work is kept alive unattended:
restart-on-abort via cron, resume from `PROGRESS.md`, and automatic rotation to free
models when tokens run out.

## Why

The agent is an OpenCode session (`ses_f31799c77ffeTq9gcYgqc4hBhg`, cwd `/home/ubuntu`).
It can stop mid-task for reasons outside its control:

- process crash / machine reboot
- model **token quota exhausted** (rate limit / daily quota)
- **context window exhaustion** on very long tasks

Once dead it cannot revive itself from within — an **external** watchdog must relaunch
it. All state needed to continue lives in this repo's [`PROGRESS.md`](../PROGRESS.md)
plus verification against disk — the agent never relies on conversation memory alone.

## Components

| Piece | Path |
|---|---|
| Watchdog script (source, in repo) | `scripts/agent-watchdog.sh` |
| Installed copy (what cron runs) | `/vol/data/benchmark/bin/agent-watchdog.sh` |
| Cron entry | `*/5 * * * * /vol/data/benchmark/bin/agent-watchdog.sh` |
| Supervisor script (source, in repo) | `scripts/meta-watchdog.sh` |
| Installed copy (what cron runs) | `/vol/data/benchmark/bin/meta-watchdog.sh` |
| Supervisor cron entry | `3,13,23,33,43,53 * * * * /vol/data/benchmark/bin/meta-watchdog.sh` |
| Liveness signal | `/vol/data/benchmark/.heartbeat` (agent `touch`es it while working) |
| Stop sentinel | `/vol/data/benchmark/TASK_COMPLETE` (existence ⇒ watchdog exits forever) |
| Restart attempt markers | `/vol/data/benchmark/.watchdog_attempts/` (rate limiting) |
| Last exit code | `/vol/data/benchmark/.watchdog_last_status` |
| Model rotation index | `/vol/data/benchmark/.watchdog_model_ix`, `.watchdog_force_model` |
| Logs | `/vol/data/benchmark/logs/watchdog.log`, `logs/agent-run.log`, `logs/meta-watchdog.log`, `logs/supervisor-run.log` |

## Decision flow (every 5 minutes)

`opencode run` is a **single-turn** command in OpenCode v2: it sends the prompt,
the agent completes ONE assistant turn ("Turn complete") and exits 0. So the
watchdog no longer runs "one turn per cron tick" — it drives a **persistent
loop**:

```
TASK_COMPLETE exists?                       -> exit (task done)
another driver holds the flock?             -> exit (only ONE driver at a time)
run/`opencode run --auto` alive, heartbeat or transcript < 15 min old? -> exit (working)
launches in last 6h >= 6?                   -> exit (crash-loop guard)

start driver (this cron invocation IS the driver, it runs for hours):
  while (not TASK_COMPLETE, turns < 200, runtime < 8h):
    turn:  opencode run --auto [--session ses_...] --title watchdog-restart "$CONTINUE_PROMPT"
    exit 0 && transcript grew  -> healthy: sleep 30s; next turn (idle phrase
                                 seen in the turn? sleep 10 min instead)
    exit != 0 && looks like quota/context exhaustion -> rotate to next
                                 free model, retry (max 3), else stop (cron relaunches)
    exit != 0 (other)           -> stop; cron relaunches (fresh session next time)
  driver surviving >= 2 turns clears .watchdog_attempts (healthy restart)
```

## Model switching

The primary session runs on the default model. The agent **cannot swap its own model
mid-conversation**; switching happens only at watchdog **restart** time via
`opencode run --model <provider/model>`:

| Order | Model |
|---|---|
| 1 | `opencode/mimo-v2.6-flash-free` |
| 2 | `opencode/muse-spark-1.3-contributor-free` |
| 3 | `opencode/ling-3.0-flash-fin-free` |
| 4 | `opencode/nemotron-3.5-lightning-free` |

- Rotation index persists in `.watchdog_model_ix`, so repeated quota failures walk the
  whole list instead of hammering one model.
- **Token refresh**: there is no timer for "when tokens come back" — cron simply retries
  every 5 min; the first attempt that is allowed to run succeeds, its exit code 0 clears
  `.watchdog_force_model`, and subsequent restarts return to the default model.
- Free-model choice is recorded in `watchdog.log` for each restart, so every resumed
  turn's model is auditable.

## Resume contract (what the restart prompt instructs)

Both continue-mode and fresh-mode prompts require the agent to:

1. read `/vol/data/benchmark/PROGRESS.md` (mirror: this repo's `PROGRESS.md`),
2. **check GitHub issues first** (both repos) — act on new/updated issues from the
   user and reply with `gh issue comment` (see "Issues loop" below),
3. verify its "Current state" checklist **against disk** before acting,
4. continue from the first unfinished step,
5. keep touching `.heartbeat`,
6. do nothing if `TASK_COMPLETE` exists.

## Issues loop (user files ideas as GitHub issues)

The user can leave ideas/instructions as GitHub issues; the agent reads them and
replies as comments. This is checked at every restart (via the prompt above) and
periodically during work.

| Repo | Issues | Status |
|---|---|---|
| `paulzierep/metagenomic-binning-benchmark` | **enabled** — idea inbox is issue #1 | working now |
| `paulzierep/COMEBin` | **disabled** — the Issues feature is off on the fork | needs a token with `Administration` scope (or the user toggles *Settings → General → Features → Issues*) |

Commands:

```bash
gh issue list -R paulzierep/metagenomic-binning-benchmark --state open --json number,title,updatedAt
gh issue comment -R paulzierep/metagenomic-binning-benchmark <n> --body "..."
```

Whenever a user issue is acted on, the agent posts a comment summarizing what was
done and documenting it in this repo (`docs/03-fixes.md` for code changes,
`docs/01-datasets.md` for datasets, `results/` for benchmarks), then updates
`PROGRESS.md`.

## GitHub status heartbeat (every 10 min)

`scripts/status-heartbeat.sh` (cron `*/10 * * * *`) pushes the agent's liveness and
**current activity** to GitHub so the user can monitor it without the agent spamming
issue comments:

- `status/current.md` — overwritten each tick; `status/status.log` — append-only timeline.
- **`README.md` line 1** — the same update is injected as the README's first line
  (marker `<!--AGENT-STATUS-->` gets replaced, so the line never duplicates).
- Liveness is read from the real heartbeat (`.heartbeat`): fresh ⇒ `alive: yes` +
  contents of `/vol/data/benchmark/.activity` (the agent updates this file whenever
  its current step changes); stale ⇒ reports "dead — watchdog will restart"; `TASK_COMPLETE`
  ⇒ "done".
- Uses `flock` + retry so it never corrupts a concurrent git operation.
- Agent contract: keep `/vol/data/benchmark/.activity` current (one line: what you are
  doing right now) — the heartbeat then tells the story on GitHub.

## Benchmark hang watchdog (independent of the agent)

`scripts/benchmark-watchdog.sh` (cron `*/5 * * * *`, installed at
`/vol/data/benchmark/bin/`) keeps the **active benchmark run** alive even if the agent
is dead/broken:

- Tracks the run registered in `/vol/data/benchmark/.active_run`
  (written by `run_comebin_baseline.sh`: pid, pgid, log file, rundir, start ts).
- **Hung** (process alive, log silent > 40 min) → kills the process group and restarts.
- **Crashed** (process gone, no `exit_code: 0` in run_meta.txt) → restarts.
- **Done** (`exit_code: 0`) → clears `.active_run`.
- Restarts go into fresh `runs/<run>_autorestartN/` dirs (raw artifacts preserved per
  attempt); max **3 auto-restarts per run per 24 h**; `flock`-protected; logs to
  `logs/benchmark-watchdog.log` and stops when `TASK_COMPLETE` exists.

This is belt-and-braces on top of the agent watchdog: agent broken → agent restarts;
benchmark hung → benchmark restarts. Both are cron-driven and terminal-independent.

## Operational notes

- **Disable / finish**: `touch /vol/data/benchmark/TASK_COMPLETE`.
- **Force an immediate restart** (testing): `touch -d '30 min ago' /vol/data/benchmark/.heartbeat`
  then wait ≤5 min or run `/vol/data/benchmark/bin/agent-watchdog.sh` manually.
- **Rate limit**: 6 restarts / 6 h. Raise `MAX_ATTEMPTS` in the script if needed.
- Restarts run with `opencode run --auto` (permissions auto-approved) so the agent can
  work unattended — acceptable here because the task is confined to this machine/repo.
- After editing `scripts/agent-watchdog.sh` in this repo, redeploy:
  `cp scripts/agent-watchdog.sh /vol/data/benchmark/bin/agent-watchdog.sh && chmod +x ...`.
