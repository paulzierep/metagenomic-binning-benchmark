# 00 — Setup (environment, tools, agent watchdog)

## Per-run logs (detailed)

Every benchmark run stores **detailed, structured logs** under `runs/<run>/`, and
the same content is **mirrored into this repo** at `runs/<run>/` (see
[`runs/README.md`](../runs/README.md)) by the status-heartbeat every 2 min and at
run end — the raw COMEBin artifacts stay on disk under `/vol/data/benchmark/runs/`:

- `run_meta.txt` — date, commit, threads, dataset, exit code, wall-clock, #bins.
- `comebin_run.log` — full stdout+stderr of `run_comebin.sh` (tee'd): stage log lines
  (`generate_aug_data`, coverage/variance, FragGeneScan/HMMER seed genes, per-epoch
  progress bars, clustering), timestamped by COMEBin's logger.
- `logs/resources.tsv` — resource sampler (every 30 s): CPU % + RSS of the run's pid
  and system memory — this is what fills the "Peak RAM" column of the README table.
- `comebin_res/` — COMEBin's own logs: `comebin.log` (internal logger), `training.log`
  (per-epoch loss/accuracy), `config.yml` (exact run config), tensorboard events.
- `comebin_out/` (disk only) — every COMEBin artifact (augmented fasta/kmer/covariance/
  depth, trained models, tensorboard events, cluster results, final bins).

**Agent activity log** `status/agent-activity.log`: verbose, append-only record of
what the agent does (one UTC-timestamped line per meaningful action), pushed to
GitHub with every heartbeat. `status/status.log` stays the 1-line liveness timeline.

Global logs: `/vol/data/logs/` (installs, launches), `/vol/data/benchmark/logs/`
(watchdog, benchmark-watchdog, status). GitHub-visible status: `status/` in this repo.

## Host

| | |
|---|---|
| CPU / RAM | 32 cores / 62 GiB |
| GPU | **none** — COMEBin runs CPU-only (`torch.cuda.is_available()` false) |
| Disk | `/vol/data` (ext4, 492 GB) — **all** repos/datasets/results live here |
| OS | Ubuntu 24.04, Docker available (not used for tool runs), no system conda |

## Directory layout (this machine)

Internal-only — the public README deliberately excludes these machine paths.

| Path | Content |
|---|---|
| `/vol/data/repos/COMEBin` | pristine upstream clone (baseline source, commit recorded per run) |
| `/vol/data/repos/metagenomic-binning-benchmark` | this repo |
| `/vol/data/datasets/` | datasets (`comebin_test_data/`, later `cami_II/`, `cami_III/`) |
| `/vol/data/envs/` | micromamba environments (`comebin`, later `checkm2`, `checkm`) |
| `/vol/data/tools/bin/micromamba` | micromamba 2.9.0 |
| `/vol/data/benchmark/runs/` | raw outputs, one directory per run |
| `/vol/data/benchmark/results/` | parsed result tables |
| `/vol/data/benchmark/logs/` | install/run/watchdog logs |
| `/vol/data/benchmark/PROGRESS.md` | live resume document for the agent |
| `/vol/data/benchmark/TASK_COMPLETE` | sentinel — watchdog stops when present |

## Package management: micromamba

```bash
# binary
/vol/data/tools/bin/micromamba            # 2.9.0
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba

# COMEBin runtime env (prefix env, not name-based!)
# Clustering deps = ONLY hnswlib, leidenalg, igraph (verified by import scan of
# cluster.py; scanpy/anndata/numba are NOT imported — do not add them, the combined
# solve hangs against the numpy=1.23/sklearn=1.1 baseline pins).
/vol/data/tools/bin/micromamba create -y -p /vol/data/envs/comebin \
  -c conda-forge -c bioconda -c pytorch \
  python=3.10 "numpy=1.23" scipy pandas "scikit-learn=1.1" "biopython=1.81" \
  pytorch cpuonly bedtools bwa samtools hmmer fraggenescan prodigal \
  tensorboard atomicwrites pyyaml networkx joblib seaborn statsmodels matplotlib \
  tqdm hnswlib igraph leidenalg checkm-genome

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
   flag is cleared (back to the default model). The prioritized primary model is
   `opencode/big-pickle` (`DEFAULT_MODEL`): healthy turns run it directly, the
   free-model rotation only engages while big-pickle itself is quota-limited, and the
   rotation index resets after every healthy run so big-pickle is used again as soon
   as its tokens are available.
4. **Safety**: max 6 restarts / 6 h (crash-loop guard); exits permanently when
   `/vol/data/benchmark/TASK_COMPLETE` exists.

Logs: `/vol/data/benchmark/logs/watchdog.log`, `agent-run.log`.

## GitHub

- Repo: https://github.com/paulzierep/metagenomic-binning-benchmark
- PAT via `git config --global credential.helper store` → `~/.git-credentials` (mode 600).
- Local clone: `/vol/data/repos/metagenomic-binning-benchmark`.
