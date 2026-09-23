# 00 — Setup (environment, tools, agent watchdog)

## Host

| | |
|---|---|
| CPU / RAM | 32 cores / 62 GiB |
| GPU | **none** — COMEBin runs CPU-only (`torch.cuda.is_available()` false) |
| Disk | `/vol/data` (ext4, 492 GB) — **all** repos/datasets/results live here |
| OS | Ubuntu 24.04, Docker available (not used for tool runs), no system conda |

## Package management: micromamba

```bash
# binary
/vol/data/tools/bin/micromamba            # 2.9.0
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba

# COMEBin runtime env (prefix env, not name-based!)
/vol/data/tools/bin/micromamba create -y -p /vol/data/envs/comebin \
  -c conda-forge -c bioconda -c pytorch \
  python=3.10 "numpy=1.23" scipy pandas "scikit-learn=1.1" "biopython=1.81" \
  pytorch cpuonly bedtools bwa samtools hmmer fraggenescan prodigal \
  tensorboard atomicwrites pyyaml networkx joblib seaborn statsmodels matplotlib \
  "scanpy>=1.9" igraph leidenalg hnswlib tqdm numba checkm-genome

# run a command inside the env
/vol/data/tools/bin/micromamba run -p /vol/data/envs/comebin <cmd>
```

Install logs: `/vol/data/logs/env_comebin_*.log`.

Rationale for pins: upstream `comebin_env.yaml` targets python3.7 / numpy1.19 /
torch1.10-cuda / sklearn0.22 — unobtainable on modern channels. We use the newest
versions that still run *unmodified* COMEBin for the **baseline** (numpy1.23 keeps
`np.int`, sklearn1.1 keeps `algorithm="full"` + `n_jobs`), then the fix batches
modernize the source instead of freezing the environment. Any deviation from this
rule is recorded in `docs/03-fixes.md`.

## Agent restart & model fallback (watchdog)

Problem: the coding agent (OpenCode session `ses_f31799c77ffeTq9gcYgqc4hBhg`) can stop
mid-task (crash, context exhaustion, token quota) and needs to resume unattended.

Mechanism — `scripts/agent-watchdog.sh`, installed at
`/vol/data/benchmark/bin/agent-watchdog.sh`, cron entry:

```
*/5 * * * * /vol/data/benchmark/bin/agent-watchdog.sh
```

1. **Liveness**: agent is expected to `touch /vol/data/benchmark/.heartbeat` while
   working; heartbeat older than 15 min ⇒ presumed dead.
2. **Restart**: `opencode run --auto --session <id>` continues the original session
   (context preserved). If the previous attempt exited non-zero, the next attempt
   starts a **fresh** session with a prompt pointing at `PROGRESS.md`.
3. **Token/quota handling**: if the failure log matches
   `rate limit|quota|429|tokens exhausted|context window ...`, the restart passes
   `--model` rotating through the free models
   (`mimo-v2.6-flash-free → muse-spark-1.3-contributor-free → ling-3.0-flash-fin-free →
   nemotron-3.5-lightning-free`). When tokens refresh, the retried run succeeds and the
   flag is cleared (back to the default model).
4. **Safety**: max 6 restarts / 6 h (crash-loop guard); exits permanently when
   `/vol/data/benchmark/TASK_COMPLETE` exists.

Logs: `/vol/data/benchmark/logs/watchdog.log`, `agent-run.log`.

## GitHub

- Repo: https://github.com/paulzierep/metagenomic-binning-benchmark
- PAT via `git config --global credential.helper store` → `~/.git-credentials` (mode 600).
- Local clone: `/vol/data/repos/metagenomic-binning-benchmark`.
