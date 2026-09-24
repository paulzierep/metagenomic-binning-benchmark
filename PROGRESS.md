# PROGRESS — metagenomic-binning-benchmark

> **Resume document.** If you (the agent) are reading this after a restart, start here,
> verify "Current state" against what is actually on disk under `/vol/data`, and
> continue from the first unfinished step. Update this file after every meaningful step.
> Live copy: `/vol/data/benchmark/PROGRESS.md` (keep both in sync: edit both, or copy
> one over the other after each update).

## Task definition

Benchmark multiple metagenomic genome binners, starting with COMEBin
(https://github.com/paulzierep/COMEBin). Document the whole process in this repo
(https://github.com/paulzierep/metagenomic-binning-benchmark) so the work can be
picked up later by anyone/any session.

Requirements from the user:
1. Modify COMEBin's source code to improve performance and fix bugs — **in a branch**,
   **one commit per batch of fixes**.
2. **Baseline first**: benchmark *unmodified* COMEBin, then apply fix batches,
   re-running the benchmark after each batch.
3. Record: parameters used, datasets used, performance/timing, bin quality with
   **CheckM2 and CheckM (v1)**.
4. Document everything in this repo.

## Standing authorizations (user-confirmed 2026-09-23 — do NOT re-ask)

1. **This VM, fully**: shell commands (incl. passwordless sudo), installing packages,
   creating/modifying anything under `/vol/data` and `/home/ubuntu`, long-running
   background jobs. Backed by `~/.config/opencode/opencode.json`
   (permissions: `*`→allow incl. external_directory). OpenCode default already allows
   `*`; the only rule that matters is `external_directory: * → allow` (that was the
   source of the prompts, because `/vol/data` is outside the session location).
2. **Both GitHub repos**: `paulzierep/metagenomic-binning-benchmark` AND
   `paulzierep/COMEBin` — git commit/push (credential helper `~/.git-credentials`,
   mode 600) and gh CLI (authenticated, `~/.config/gh/hosts.yml`).
3. **Issues workflow**: the user files ideas/instructions as GitHub **issues**; the
   agent reads them and **comments** back (see below). ⚠️ the Issues feature is
   currently DISABLED on `paulzierep/COMEBin` (needs a token with Administration scope
   or a manual repo-Settings toggle — user must flip it or grant scope). Ideas go to
   the benchmark repo for now (idea box: issue #1).

## Run logging — where everything is (per run: `runs/<run>/`)

| Path | Content | Granularity |
|---|---|---|
| `run_meta.txt` | date, source commit, threads, dataset, exit_code, wall time, #bins | start + end |
| `comebin_run.log` | **full stdout+stderr of `run_comebin.sh`** — verbose timestamps, every stage (`generate_aug_data`, coverage, FragGeneScan, epochs with progress bars, clustering) | live (tee) |
| `logs/resources.tsv` | per-run resource sampler: every 30 s — CPU %, RSS (GB) of the wrapper pid, system mem used | 30 s |
| `logs/sampler.out` | sampler stderr | — |
| `comebin_out/` | ALL COMEBin internal artifacts: `data_augmentation/` (fasta, kmer, covariance, depth), trained `models/`, `tensorboard*/`, `cluster_res/` (embeddings, leiden runs, bins) | — |
| (parent) `run_meta.txt` JSON-style CSV in `results/` | parsed metrics row | after eval |

**Everything above is mirrored into this repo** at `runs/<run>/` (small log files
only — `run_meta.txt`, `comebin_run.log`, `logs/resources.tsv`, `comebin_res/{comebin.log,
training.log,config.yml}`; raw artifacts stay on disk). The status-heartbeat re-syncs
every 2 min and at run end, so per-run logs reach GitHub within ~2 min.
`runs/README.md` documents the layout.

**Agent activity log** `status/agent-activity.log`: the VERBOSE companion to the
1-line liveness timeline in `status/status.log`. The agent appends one UTC-timestamped
line per meaningful action (started/finished X, decisions, errors) and it is pushed
with every heartbeat. Watchdog restart prompts mandate this.

**Command lines**: each run's `run_meta.txt` records the exact commands used
(`cmd_wrapper:`, `cmd_train_py:`, `cmd_from_log:` lines); templates for every
benchmark tool run — COMEBin, CheckM2, CheckM, dataset prep — live in
`docs/06-benchmark-commands.md`.

Global: `/vol/data/logs/*` = installs + launch logs; `/vol/data/benchmark/logs/*` = heartbeat, watchdog, benchmark-watchdog; `status/` in this repo = GitHub-visible status.

## Run logging — how to read phases

Watch progress: `tail -f runs/<run>/comebin_run.log` (epoch bars update in place, use
`tr '\r' '\n'`). First run finished → `run_meta.txt` gets `exit_code: 0` and `wall_s:`.

## Resource policy (user: max resources for the benchmark, keep some for the agent, don't break anything)

- Benchmark runs use the full machine: **32 threads, full RAM** (host 32 cores / 62 GiB).
  Measured during baseline training: load ~31, main.py ~3036% CPU, 7.6/62 GB used.
- Agent keeps ~1–2 cores + light RAM (opencode serve, watchdog, status cron, git/gh).
- Safe headroom is monitored every 2 min by the status heartbeat: every `status/status.log`
  row includes `mem=` and `load=`; a RAM spike during clustering/HNSW would show there.
- Safety rules:
  - NEVER run CheckM2/CheckM evaluation concurrently with a COMEBin run (RAM/CPU spikes).
  - NEVER kill or edit an in-progress benchmark (pristine source guarantees baseline validity).
  - All long jobs are `nohup`-detached so terminal close / agent restart never kills them.

## Issues workflow (user-facing)

- Where to file ideas: any issue in `paulzierep/metagenomic-binning-benchmark`
  (inbox issue #1 documents the format), or — once enabled — `paulzierep/COMEBin`.
- Agent behavior: at restart (watchdog prompt) and repeatedly during work, run
  `gh issue list -R <repo> --state open --json number,title,updatedAt` on both repos;
  act on new/updated issues; reply with `gh issue comment`; record in this file.
- Commands:
  `gh issue list -R paulzierep/metagenomic-binning-benchmark --state open --json number,title,updatedAt`
  `gh issue comment -R paulzierep/metagenomic-binning-benchmark <#n> --body "..."`

## Decisions (confirmed by user)

| Topic | Decision |
|---|---|
| Datasets | COMEBin demo data (first), then CAMI II challenge, then CAMI III challenge |
| Workflow | Unmodified baseline → batched fixes, benchmark after each batch |
| Environment | micromamba + conda envs (no Docker for tool execution) |
| Storage | all git repos, datasets, benchmark data under `/vol/data` |
| Agent restart | cron watchdog `scripts/agent-watchdog.sh`: restarts on abort, rotates to free models on quota exhaustion |
| Permissions | full authorization on VM + both repos (see above) |

## Directory layout (authoritative)

| Path | Content |
|---|---|
| `/vol/data/repos/COMEBin` | pristine upstream clone (record `git rev-parse HEAD` per run) |
| `/vol/data/repos/metagenomic-binning-benchmark` | this repo |
| `/vol/data/datasets/comebin_test_data/` | COMEBin demo dataset extracted |
| `/vol/data/datasets/comebin_test_data.zip` | original 5.58 GB download |
| `/vol/data/datasets/cami_II/`, `cami_III/` | CAMI datasets (TODO) |
| `/vol/data/envs/comebin` | micromamba env for COMEBin |
| `/vol/data/envs/checkm2`, `/vol/data/envs/checkm` | evaluation envs (TODO) |
| `/vol/data/tools/bin/micromamba` | micromamba 2.9.0 |
| `/vol/data/benchmark/runs/` | raw outputs per run |
| `/vol/data/benchmark/results/` | parsed tables per run |
| `/vol/data/benchmark/logs/` | logs |
| `/vol/data/benchmark/TASK_COMPLETE` | watchdog sentinel |

## Environment facts

- `MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba`
- Run in env: `/vol/data/tools/bin/micromamba run -p /vol/data/envs/comebin <cmd>`
- Host: 32 cores, 62 GB RAM, **no GPU** (CPU-only PyTorch), ~460 GB free on `/vol/data`.
- OpenCode binary `/home/ubuntu/.opencode/bin/opencode`; primary/default model
  `opencode/big-pickle`; free models for fallback (only when big-pickle is quota-limited):
  `opencode/mimo-v2.6-flash-free`, `opencode/muse-spark-1.3-contributor-free`,
  `opencode/ling-3.0-flash-fin-free`, `opencode/nemotron-3.5-lightning-free`.
- Session ID of the primary agent session: `ses_f31799c77ffeTq9gcYgqc4hBhg` (cwd `/home/ubuntu`).
- GitHub PAT stored in `~/.git-credentials` (600) + gh CLI (`~/.config/gh/hosts.yml`).

## COMEBin demo dataset

- Google Drive file id `1xWpN2z8JTaAzWW4TcOl0Lr4Y_x--Fs5s` (gdown).
- Contigs: `comebin_test_data/BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta`
  — **29,434 sequences**, ≈53 MB.
- BAM: `comebin_test_data/bamfiles/SRR5720343.bam` — 5.07 GB (verify/refresh `.bai`).
- `excepted_output/` = upstream reference run incl. CheckM output → validate against it.
- Quality scored by marker genes via CheckM2/CheckM; no read-level truth needed.

## Known COMEBin bugs / perf issues (candidates for fix batches)

Full source review (~3.1 kLOC) done. Findings:

**Crashes on modern libs**
1. `np.int` (removed NumPy ≥1.24): `COMEBin/get_augfeature.py` ~L41,53,66; `COMEBin/utils.py` ~L109,119.
2. `KMeans(n_jobs=-1, algorithm="full")` (removed sklearn ≥1.0) + private import
   `sklearn.cluster._kmeans.*`: `COMEBin/cluster.py` ~L103 and ~L13.

**Correctness**
3. Fractional bedtools depth truncated via `int(float(...))` → coverage mean/var wrong:
   `data_aug/gen_cov.py`, `data_aug/gen_var.py`.
4. `filter_small_bins.gen_bins`: `bin_name += 1` inside per-contig loop → bin file
   numbering garbage.
5. No RNG seeds: augmentation (`random.*`), Leiden optimizer (no `set_rng_seed`) →
   runs not reproducible (blocks fair benchmarking).
6. Small-dataset crash: `run_comebin.sh` caps `batch_size` by *all* contigs; training
   filters ≥1000 bp; `DataLoader(drop_last=True)` → zero batches → `NameError: logits`.
7. `accuracy(..., topk=(1,5))` needs ≥5 views; `-n <5` crashes.
8. `os.makedirs(outdir)` w/o `exist_ok=True` in `generate_augfasta_and_saveindex.py`.
9. `run_comebin.sh`: `realpath` on non-existent output dir; no `set -euo pipefail`;
   `$?` checks after `if` blocks fragile.

**Performance**
10. `gen_kmer.py`: pure-Python `itertools.tee` sliding-window k-mer counting — hot loop,
    vectorization target.
11. `gen_cov.py`/`gen_var.py`: materialize per-base depth lists → accumulate
    `Σv·len`, `Σv²·len` in closed form (RAM + CPU win).
12. `cluster.py`: `in` scans on arrays/lists (`gen_seed_idx`, `is_membership_fixed`)
    are O(n·m) → sets.
13. `get_augfeature.py`: reads each TSV header twice + same file 3× for names.
14. Leiden grid = 8×5×3 = 120 unseeded runs in a Pool → sweep/prune/seeding.

**Benchmark integrity:** baseline = pristine upstream commit
(`/vol/data/repos/COMEBin`, record `git rev-parse HEAD`), unseeded nondeterminism
included; fixes land on branch `comebin-optimizations` in this repo.

## Current state

- [x] `/vol/data` layout created; micromamba 2.9.0 installed
- [x] COMEBin test dataset downloaded (5.58 GB) **and extracted** (6.4 GB; 29,434 contigs)
- [x] Full COMEBin source review (findings above)
- [x] Base env `/vol/data/envs/comebin` installed (python3.10, numpy1.23, sklearn1.1,
      biopython1.81, pytorch-cpu, samtools/bwa/bedtools/hmmer/FragGeneScan/prodigal,
      hnswlib/igraph/leidenalg; scanpy/numba NOT needed — never imported)
- [x] Eval envs built: `/vol/data/envs/checkm2` (CheckM2 v1.1.0) + `/vol/data/envs/checkm`
      (checkm v1; repaired with `setuptools<81` → `pkg_resources` on py3.14)
- [x] Docs written & pushed to `main` (README, PROGRESS, docs/00–06, scripts/, .gitignore)
- [x] gh CLI 2.45.0 installed + authenticated; idea-inbox issue #1 created
- [x] Standing permissions configured (`~/.config/opencode/opencode.json`)
- [x] Watchdogs installed (cron `*/5` agent + `*/5` benchmark-hang + `*/2` status-heartbeat)
- [x] Per-run detailed logs mirrored into repo `runs/<run>/` (run_meta, comebin_run.log,
      resources.tsv, comebin_res/*) — baseline row already live on GitHub
- [x] Command lines documented: `docs/06-benchmark-commands.md`; per-run `run_meta.txt`
      records `cmd_wrapper:` / `cmd_train_py:` / `cmd_from_log:`
- [x] Status heartbeat live: German-time (Europe/Berlin) banner on README line 1 +
      `status/current.md` (mem+load) + `status/status.log` + verbose
      `status/agent-activity.log` — pushed every 2 min. Now embeds a **live epoch
      probe** from the active run (banner shows `epoch N/200 · x/28 batches`), so
      status never looks frozen.
- [x] Issue #3 "I think comebin is stuck" — answered 2026-09-23 16:33 UTC with
      live evidence (main.py ~3120% CPU on 32 cores, loss 3.33→3.16, Top1→94%,
      46/200 epochs, ETA ~6 h worst case): run is healthy; the frozen look was a
      stale banner snapshot → fixed with the live probe above.
- [x] Binaries verified: run_FragGeneScan.pl, hmmsearch, bedtools, bwa, samtools, checkm
- [x] BAM indexed (`SRR5720343.bam.bai`)
- [x] Small benchmark dataset (issue #2): 300 top-length contigs + real overlapping reads
      → `/vol/data/datasets/comebin_small` (94 MB); functional test runner ready
      (`scripts/run_small_test.sh`). `small_test_v4` passed end-to-end on 2026-09-24
      (30 epochs, 3 non-empty bins, wall 122 s); CheckM2 mean 26.07% completeness /
      2.02% contamination and CheckM v1 mean 29.08% / 0.71%. Results:
      `results/small_test_v4.csv`.
- [x] CAMI II marine assemblies downloaded + **md5 verified** (`1c054a45…`), 9.42 GB;
      extraction running; marine short-reads URL recorded (docs/01)
- [x] CAMI II marine sample 0 (short-read): reads archive downloaded (5.2 G, 2026-09-23)
      + extracted → `reads_0/…/reads/anonymous_reads.fq.gz` (**interleaved paired-end**,
      35.25 M reads ≈ 17.6 M pairs) + `reads_mapping.tsv.gz` (maps reads → **genome**,
      not contig). **Input decision** (docs/01): contigs = `anonymous_gsa.fasta.gz`
      subset ≥2,000 bp (**41,988 contigs**; full set 1.48 M is not COMEBin-feasible),
      reads = all → `bwa mem -p` single BAM; ground truth = `binning_gs.tsv` subset.
      `scripts/prep_cami2_marine.sh` + env-overridable `run_comebin_fix.sh`
      (CONTIGS/BAMDIR/MODE=`cami2`) ready; prep is CPU-bound → runs post-baseline
- [x] checkm2 reference DB downloaded + extracted (`/vol/data/benchmark/checkm2db/`,
      `uniref100.KO.1.dmnd` 3.08 GB); **checkm v1 reference data INSTALLED + verified**:
      official tarball `checkm_data_2015_01_16.tar.gz` (288,590,617 B, `gzip -t` OK)
      → extracted to `/vol/data/benchmark/checkm_ref/`, `checkm data setRoot` done,
      CheckM v1.1.3 `taxon_list` loads markers OK (commands in docs/06)
- [x] **Fix batch 1 (original) committed + pushed to fork** (branch
      `comebin-optimizations`, commit `03670d6a`, worktree
      `/vol/data/repos/COMEBin-opt`): sequential bin numbering + float coverage
      depth (gen_cov.py + gen_var.py) — see `docs/07-fix-batches.md`
- [x] **Fork updated by user (issue #5)**: origin/master → `1b476a4` (v1.1.0:
      gen_cov.py float64/Welford rewrite — coverage fix now upstream; gen_var.py
      removed; new flags `-w -m -d cpu -s seed -E -V`). Rebased fix work onto it:
      branch **`comebin-optimizations-v11`** @ `95f5ea8` (worktree
      `/vol/data/repos/COMEBin-v11`): sequential bin numbering + no-empty-bins
      re-applied; py_compile + synthetic functional test PASS; pushed
- [x] **Issue #4 "why agent often broken" — root cause found + fixed**: watchdog
      log showed 17:35–18:41 outage = crash-loop rate limit hit by the OLD
      one-shot-per-cron design. Persistent driver loop now keeps the agent on
      the SAME session turn-after-turn; crash-guard markers only count FAILED
      launches; **model in use is now logged** (watchdog.log `model=…` per turn;
      status/current.md + status.log `model=` from the transcript; supervisor
      meta-watchdog layer added). All committed @ `ec41276`
- [x] **Supervisor hardening follow-up**: owner-scoped primary liveness,
      successful-turn-only crash reset, 1 h agent/30 min supervisor timeouts,
      child lock-FD closure, official service/API + actual remote-SHA checks,
      source/installed checksum enforcement, safe benchmark PID/PGID/start
      validation and atomic mode/source handoff, retryable issue markers with
      before/after comment IDs, and shared repo locks. Small/fix/eval launchers
      refuse overlap; small test now records its promised resource timeline.
- [x] **Issue #2 directives recorded** (docs/08): (a) functional tests start
      on the 94 MB small real-data set; (b) only after that end-to-end run
      passes, build a medium derived set (target 3,000 contigs, hard cap 5 GB);
      (c) large benchmarks only after major commits; (d) dataset/space plan
      includes human host-associated CAMI II (Multisample HMP / Toy Human
      Microbiome), 391 GB free, planned data ≤ ~105 GB. Replies posted.
- [x] **COMPLETE: baseline rerun + evaluation (2026-09-24)** — registered watchdog run
      `baseline_rerun_autorestart1`, exit_code 0, wall_s 24,327 (~6.75 h), 200/200
      epochs, 99.19% Top1. CheckM2: 60 bins, 25.01% mean completeness, 2.98%
      mean contamination; CheckM v1 lineage workflow completed with the Python
      3.10-compatible environment (60 bins; 21.23% mean completeness / 3.40%
      mean contamination). Evidence: `runs/baseline_rerun_autorestart1/`
      and `eval/checkm2/quality_report.tsv`. No benchmark was active when this
      evaluation completed; the medium run is tracked separately below.
- [x] **Long-run launch safety guard (2026-09-24)** — multi-hour baseline/fix
      runs must be launched detached in a fresh run directory, then verified via
      `.active_run` and handed off to `benchmark-watchdog.sh`; never run them in
      a foreground tool call, delete an existing run directory, or overwrite its
      evidence. The primary-agent prompts now enforce this on future turns.
- [x] **C6 snapshot identity remediation (2026-09-24)** — benchmark-watchdog and
      meta-watchdog now accept only an existing immutable snapshot tied to the
      registered run family plus the exact registered run directory; unrelated
      live PIDs still fail closed. Source and installed copies were syntax-checked
      and the active snapshot was verified without a restart.
- [x] **Issue #2 small-data fix validated end-to-end** — the observed
      `aug0_datacoverage_mean.tsv` contained 29,434 BAM-header references while
      the reduced assembly had 300. COMEBin branch `comebin-small-fix` commits
      `5c77bc8` (producer/consumer alignment), `a0be243` (30-epoch functional-test
      option), and `c8f22e4` (sklearn KMeans compatibility) are pushed. Dataset
      builders emit explicit BED intervals and use `samtools -L`; the full-header
      BAM was preserved after the reheader experiment. `small_test_v4` is the
      verified passing gate. `run_small_test.sh` now rejects a masked zero-bin
      success, and `run_eval.sh` validates both evaluation artifacts.
- [x] **Supervisor C6 remediation (2026-09-23 21:42 UTC)**: deterministic terminal
      failures are recorded and cleared instead of retried; replacement runners
      use committed immutable snapshots; baseline wrapper failures now persist
      `exit_code`; status labels cleared runs as not active. Fix commit: `2d61909`
      (status truthfulness follow-up: `73aa0dd`).
- [x] **Issues #6/#7/#8 triaged (20:55 UTC)**: #6 optimization → strategy doc;
      #7 optimization plan → `docs/09-optimization-strategy.md` + README link
      (flowchart, decision gate, adaptive-param ideas); #8 zenodo data archiving →
      reply posted with proposed package/prep + what I need (token or manual upload)
- [x] **docs/09-optimization-strategy.md written and linked from README** (with
      benchmark-repo commit)
- [x] **Release preservation record published (issue #8 remains open for the
      latest license/metadata clarification)**: production Zenodo record
      [10.5281/zenodo.22935025](https://doi.org/10.5281/zenodo.22935025), version 1,
      CC BY 4.0. The 95,216,539-byte archive and 3,650-byte public manifest were
      uploaded; clean extraction and all 18 manifest entries verified. A fresh
      unauthenticated record API request returned HTTP 200; safe deposition
      metadata is stored at `/vol/data/benchmark/meta/zenodo_comebin_small.json`.
      A later owner comment requested MIT plus expanded metadata; no silent
      license change was made, and issue #8 is intentionally not marked closed.
- [x] **Symlink-safe artifact checks and guarded medium builder**: `run_eval.sh`,
      `run_small_test.sh`, `run_comebin_baseline.sh`, and `run_comebin_fix.sh`
      follow COMEBin's bin-directory symlink and reject zero/empty-bin success;
      `make_medium_dataset.sh` refuses overwrites and overlaps with the launch
      lock; `make_results_csv.py` derives bin counts from evaluator rows for older
      baseline metadata. Deployed copies are byte-identical to source. A
      baseline evaluation rerun with the deployed evaluator returned
      CheckM2/CheckM rc=0, and the corrected baseline CSV records 60 bins.
- [x] **Issue #9 triaged (2026-09-24 04:39 → 04:45 UTC)**: per-run failure/next-step
      explanation requested → new README section **“Run history — what happened and
      what’s next”** (one row per run attempt: result, root cause, next step, commit
      links; performance-table baseline row now links to it); summary comment posted
      (`#issuecomment-5807827932`).
- [x] **Issue #10 triaged (2026-09-24 04:54 → 05:05 UTC)**: fewer epochs for
      functional tests → `run_comebin.sh` (branch `comebin-small-fix`) gained an
      optional **`-E INT`** flag passing `--epochs` (default 200 = unchanged
      upstream behavior; pushed as `a0be243`); `run_small_test.sh` gained
      **`EPOCHS`** env, default 30, recorded in `run_meta.txt`, passed only when
      the CLI supports `-E`; benchmark runs keep the full 200 epochs. Comment:
      `#issuecomment-5807975873`.
- [x] **← COMPLETE: baseline rerun + eval** (2026-09-24) — registered watchdog run `baseline_rerun_autorestart1`, exit_code: 0, wall_s: 24327 (~6.75h), 200/200 epochs, 99.19% Top1 accuracy. Evaluation: CheckM2 60 bins, 25.01% mean completeness, 2.98% mean contamination (65s); CheckM v1: 60 bins, 21.23% mean completeness, 3.40% mean contamination (rerun in
      the COMEBin env py3.10 + `LD_LIBRARY_PATH` workaround after the standalone
      checkm env errored: `Models must be parsed before identifying HMM hits`).
      Fixes applied: hmmer 3.1b2 (replaced 3.4, resolves `--cut_tc` on TC-less bacar_marker.hmm), sklearn KMeans `n_jobs=-1` removed (358ddd8), `run_comebin_baseline.sh` BENCHMARK_RESUME (8bb73dd). Commit `904f649`. Evidence: `runs/baseline_rerun_autorestart1/eval/checkm2/quality_report.tsv`
      and `runs/baseline_rerun_autorestart1/eval/checkm/out/storage/bin_stats_ext.tsv`;
      parsed row in `results/baseline_rerun_autorestart1.csv` (60 bins). Pushed.
- [x] **Small end-to-end gate** — `small_test_v4` completed via
      `scripts/run_small_test.sh` with 3 non-empty bins; CheckM2 and CheckM v1
      outputs are verified and mirrored in the repository.
- [x] **Medium 3,000-contig derivative (≤5 GB)**: built and verified at
      `/vol/data/datasets/comebin_medium` (3,000 contigs, 421,631,278 bytes;
      `PROVENANCE.txt` and MD5s recorded). CheckM2: 16 bins, 35.93% mean completeness,
      4.67% mean contamination (HQ=0, MQ=2); CheckM v1: 16 bins, 33.83% mean completeness,
      6.03% mean contamination (HQ=0, MQ=3). The detached v1.1.0 run
      `runs/medium_v11_20260924` completed evaluation; terminal status confirmed.
      Aggregate evidence: `results/medium_v11_20260924.csv`; per-bin joined table
      `runs/medium_v11_20260924/per_bin_results.csv` (CheckM2 x CheckM v1, from
      `scripts/make_per_bin_csv.py`); CheckM2-only `runs/medium_v11_20260924/checkm2_per_bin.csv`.
- [ ] **ACTIVE: fix_v11 full-large benchmark** — `runs/fix_v11_20260924`
      registered in `.active_run` (mode fix) at 2026-09-24T10:37Z; source
      COMEBin-v11 @ `95f5ea8` (branch comebin-optimizations-v11, clean), full
      demo dataset (29,434 contigs), 32 threads, seed 42, 200 epochs (observed
      cadence ~2.1–2.5 min/epoch ⇒ ~7.5 h total, ETA ≈ 18:00 UTC, 32-core CPU
      ~2900%, RAM 9.4 GB). Next after
      terminal status: `scripts/run_eval.sh runs/fix_v11_20260924` (CheckM2 +
      CheckM v1) → `make_results_csv.py` → per-bin CSV → README/docs-11 row.
- [ ] CAMI II marine sample 0 benchmark run → human host-associated sample →
      CAMI III

- [x] **Issue #12 plots (2026-09-24 ~10:42 UTC)**: `scripts/make_per_bin_plots.py`
      generates per-bin bar charts (`runs/<run>/per_bins.png`, CheckM2 + CheckM v1
      comp/cont per bin) and a comparison scatter
      (`results/figures/comp_vs_cont_all-runs.png`, one point per bin, color = run)
      via the comebin env's matplotlib. Run for baseline_rerun_autorestart1,
      small_test_v4, medium_v11_20260924; each run re-renders its figures after
      eval. Same-dataset comparisons accumulate (fix_v11 vs baseline once live).

- [x] **Issues #7/#15/#16 triaged (2026-09-24 10:26–10:44 UTC)**: #7 — the
      optimization flowchart is now rendered live in the README (colored mermaid,
      fuller Current/Next text; `docs/09` synced). #15 — per-bin results for ALL
      evaluated runs stored under `runs/<run>/per_bin_results.csv` (generator
      `scripts/make_per_bin_csv.py`); root-level `medium_v11_20260924_checkm2_stats.csv`
      moved to `runs/medium_v11_20260924/checkm2_per_bin.csv`. #16 — watchdog now
      defaults to `opencode/big-pickle` (`c42fa84`), rotation only on quota.
      Commits: `869754a` (per-bin + README), `c42fa84` (watchdog big-pickle).

## Watchdog / restart

`scripts/agent-watchdog.sh` (installed at `/vol/data/benchmark/bin/`, cron `*/5 * * * *`):
stale heartbeat (>15 min) → `opencode run` continues session
`ses_f31799c77ffeTq9gcYgqc4hBhg`; if that failed → fresh session with resume prompt.
Both prompts first check GitHub issues for user instructions. On quota/token/context
errors it forces `--model` rotation through the free model list; a successful run
clears the flag (back to default). Rate limit 6 restarts / 6 h; stops when
`TASK_COMPLETE` exists. **Agent: touch `/vol/data/benchmark/.heartbeat` regularly.**