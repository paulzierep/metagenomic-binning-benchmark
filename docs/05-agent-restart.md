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
| Liveness signal | `/vol/data/benchmark/.heartbeat` (agent `touch`es it while working) |
| Stop sentinel | `/vol/data/benchmark/TASK_COMPLETE` (existence ⇒ watchdog exits forever) |
| Restart attempt markers | `/vol/data/benchmark/.watchdog_attempts/` (rate limiting) |
| Last exit code | `/vol/data/benchmark/.watchdog_last_status` |
| Model rotation index | `/vol/data/benchmark/.watchdog_model_ix`, `.watchdog_force_model` |
| Logs | `/vol/data/benchmark/logs/watchdog.log`, `logs/agent-run.log` |

## Decision flow (every 5 minutes)

```
TASK_COMPLETE exists?                       -> exit (task done)
restarts in last 6h >= 6?                   -> exit (crash-loop guard)
heartbeat younger than 15 min?              -> exit (agent alive)

classify previous failure from agent-run.log tail:
  matches rate.?limit|quota|429|tokens exhausted|context window...  -> QUOTA=1
  previous exit code != 0                                           -> plain failure

model selection:
  QUOTA=1                -> force --model <next free model> (rotation, see below),
                            set .watchdog_force_model
  previous exit == 0     -> clear forced flag (back to default model)
  forced + failed again  -> rotate to next free model

session selection:
  previous exit == 0     -> opencode run --session ses_... (continue, keeps context)
  previous exit != 0     -> opencode run            (fresh session, prompt says:
                            "read PROGRESS.md first, verify disk, continue")

append attempt marker, log everything, run agent with --auto
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

## Operational notes

- **Disable / finish**: `touch /vol/data/benchmark/TASK_COMPLETE`.
- **Force an immediate restart** (testing): `touch -d '30 min ago' /vol/data/benchmark/.heartbeat`
  then wait ≤5 min or run `/vol/data/benchmark/bin/agent-watchdog.sh` manually.
- **Rate limit**: 6 restarts / 6 h. Raise `MAX_ATTEMPTS` in the script if needed.
- Restarts run with `opencode run --auto` (permissions auto-approved) so the agent can
  work unattended — acceptable here because the task is confined to this machine/repo.
- After editing `scripts/agent-watchdog.sh` in this repo, redeploy:
  `cp scripts/agent-watchdog.sh /vol/data/benchmark/bin/agent-watchdog.sh && chmod +x ...`.
