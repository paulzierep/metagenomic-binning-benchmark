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
| Heartbeat script (source, in repo) | `scripts/status-heartbeat.sh` |
| Installed copy (what cron runs) | `/vol/data/benchmark/bin/status-heartbeat.sh` |
| Heartbeat cron entry | `*/2 * * * * /vol/data/benchmark/bin/status-heartbeat.sh` |
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
primary-session `opencode run` alive, or heartbeat/transcript < 15 min old? -> exit
failed driver launches in last 6h >= 6?     -> exit (crash-loop guard)

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

## GitHub status heartbeat (every 2 min)

`scripts/status-heartbeat.sh` (cron `*/2 * * * *`) pushes the agent's liveness and
**what is actually happening** to GitHub so the user can monitor it without the
agent spamming issue comments:

- `status/current.md` — overwritten when the status changes; `status/status.log` —
  append-only timeline of CHANGES (not beeps), incl. the `model=` used and the
  live `epoch=l/a` loss/accuracy of the running benchmark.
- **`README.md` line 1** — the same update is injected as the README's first line
  (marker `<!--AGENT-STATUS-->` gets replaced, so the line never duplicates), and
  the **"Benchmark runs — performance" table's Status cell** is refreshed from the
  live training log (epoch/loss/top1) so the README never shows a frozen epoch.
- **Truthfulness**: the headline numbers (epoch/loss/accuracy, model, mem/load) are
  derived from REAL files — the live `training.log`, the run transcript, `/proc` —
  never assumed. The agent's `.activity` note is displayed age-tagged
  ("agent note · N min old") so a stale note can never masquerade as ground truth.
- Liveness is read from the real heartbeat (`.heartbeat`): fresh ⇒ `alive: yes`;
  stale ⇒ reports "dead — watchdog will restart"; `TASK_COMPLETE` ⇒ "done".
- **Skip-if-unchanged**: generated files are only rewritten + committed when the
  meaningful status changed, so at 2-min cadence idle periods produce no commits.
- Uses a per-script `flock` plus the shared `/tmp/bench-repo.lock`, and commits
  only heartbeat-owned paths with `git commit --only`; it verifies
  `HEAD=origin/main` after push instead of mistaking a recent local commit for a
  successful GitHub push.
- Agent contract: keep `/vol/data/benchmark/.activity` current (one line: what you are
  doing right now) — the heartbeat then tells the story on GitHub.

## Benchmark hang watchdog (independent of the agent)

`scripts/benchmark-watchdog.sh` (cron `*/5 * * * *`, installed at
`/vol/data/benchmark/bin/`) keeps the **active benchmark run** alive even if the agent
is dead/broken:

- Tracks the run registered in `/vol/data/benchmark/.active_run`: pid, pgid,
  log file, rundir, start timestamp, mode and source repo. Legacy baseline
  entries contain the first five fields and default to mode `baseline`.
- **Hung** (verified COMEBin runner alive, log silent > 40 min) → kills only
  its registered process group/wrapper; it refuses to kill a reused or
  unrelated PID and never uses broad `pkill -f`.
- **Crashed** (process gone, no `exit_code: 0` in run_meta.txt) → restarts.
- **Done** (`exit_code: 0`) → clears `.active_run`.
- Restarts preserve the registered mode/source (`baseline`, `fix`, or `small`),
  use a stable pre-autorestart name for the rolling 24 h budget, and write to a
  fresh `runs/<run>_autorestartN/` directory. Legacy five-field registrations
  default safely to the pristine baseline. `flock`-protected; logs to
  `logs/benchmark-watchdog.log`; stops when `TASK_COMPLETE` exists.

This is belt-and-braces on top of the agent watchdog: agent broken → agent restarts;
benchmark hung → benchmark restarts. Both are cron-driven and terminal-independent.

## Meta-supervisor and issue updates

`scripts/meta-watchdog.sh` runs at minutes 3/13/23/33/43/53. It validates the
four exact cron entries and executable scripts, checks `opencode service status`
plus `/api/info`, uses the agent-driver flock and a primary-session-scoped process
match, checks real `HEAD=origin/main` parity, validates the registered benchmark
command/log, and records issue updates under `status/meta/`.

An issue's `updatedAt` marker advances **only after a successful supervisor
triage**. Failed or over-budget escalations therefore remain pending. After a
successful response, the marker is refreshed to the issue's latest timestamp,
so the agent's own GitHub comment does not create an endless self-escalation
loop. `META_WATCHDOG_NO_LLM=1` provides a checks-only verification mode.

## Operational notes

- **Disable / finish**: `touch /vol/data/benchmark/TASK_COMPLETE`.
- **Force an immediate restart** (testing): `touch -d '30 min ago' /vol/data/benchmark/.heartbeat`
  then wait ≤5 min or run `/vol/data/benchmark/bin/agent-watchdog.sh` manually.
- **Rate limit**: 6 restarts / 6 h. Raise `MAX_ATTEMPTS` in the script if needed.
- Restarts run with `opencode run --auto` (permissions auto-approved) so the agent can
  work unattended — acceptable here because the task is confined to this machine/repo.
- After editing watchdog/heartbeat sources, deploy all four atomically and
  verify byte identity with their `/vol/data/benchmark/bin/` copies before push.
