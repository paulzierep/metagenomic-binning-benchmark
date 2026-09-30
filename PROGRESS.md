# PROGRESS — metagenomic-binning-benchmark

> **Resume document.** If you (the agent) are reading this after a restart, start here,
> verify "Current state" against what is actually on disk under `/vol/data`, and
> continue from the first unfinished step. Update this file after every meaningful step.
> Live copy: `/vol/data/benchmark/PROGRESS.md` (keep both in sync: edit both, or copy
> one over the other after each update).

> ⚠️ **Before any git operation on `paulzierep/COMEBin` (branch, commit, push, rebase),
> read [`docs/12-comebin-master-divergence.md`](docs/12-comebin-master-divergence.md).**
> `master` tracks the upstream v1.1.0 baseline: never force-push it, never reset it
> backwards, always `git fetch` before branching. 4 of the 5 older pre-v1.1.0 bug
> fixes are already fixed upstream in v1.1.0 — re-porting them conflicts and is
> wasted work. Keep this note when you rewrite the file.

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
| `results/` in the repo | parsed tables per run (tracked, embedded in README) |
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
- [x] Issue triage (2026-09-26): reviewed open issues #22 (summary table), #21 (seeds), #20 (optimization ideas), #19 (better plots), #6 (optimization); posted initial comments
- [x] **Agent restart resumed (2026-09-29)**: read PROGRESS.md, checked GitHub issues via `gh issue list`; triaged without duplicating existing responses; verified disk state: sweep driver running cells 1-12 of 24-cell medium grid on COMEBin-v11-sweep@95f5ea8; sweep_004_temp005 completed (temp=0.05, exit 0, eval OK, 13 bins, CheckM2 43.55/6.77); sweep_005_temp030 completed (temp=0.30, exit 0, eval OK, 17 bins, CheckM2 33.38/3.73); sweep_006_temp050 completed (temp=0.50, exit 0, eval OK, 17 bins, CheckM2 34.33/3.92); sweep_007_emb1024 completed (emb=1024, temp=ref, 15 bins, CheckM2 38.40/4.76 HQ 0 MQ 2); sweep_008_emb4096 completed (emb=4096, temp=ref, 16 bins, CheckM2 rc 0); sweep_009_embcov1024 completed (emb_cov=1024, temp=ref, 16 bins, CheckM2 35.80/4.12 HQ 0 MQ 2); .heartbeat touched; agent-activity.log updated
- [x] **State update (2026-09-29T10:18UTC)**: sweep_010_embcov4096 now running at epoch 88/200 (temp=ref, emb_cov=4096, seed=42, 8 threads). Cells 1-10 complete; cells 11-24 pending. Sweep ETA ~2026-10-02 UTC per heartbeat. Active run verified: /vol/data/benchmark/runs/sweep_010_embcov4096, source COMEBin-v11-sweep@95f5ea8, medium 3000-contig dataset.
- [x] **Run completion (2026-09-29T10:26UTC)**: sweep_010_embcov4096 training+eval completed exit 0, 17 bins, CheckM2 rc 0 (34.10% compl, 4.50% cont, HQ 0 MQ 4), CheckM rc 0 (30.52% compl, 4.24% cont). Sweep driver proceeding to cells 11-24 of 24-cell medium grid. ETA ~2026-10-02 UTC. sweep_011_batch512 completed (exit 0, 17 bins, CheckM2 34.33/3.92); sweep_012_batch2048 now active running cell 12 of 24 (8 threads, seed 42, batch=2048, medium dataset). Cells 1-11 complete, cell 12 running.
- [x] **State update (2026-09-29T13:28UTC)**: sweep_013_edges80 running cell 13/24 (epoch ~171/200, temp=ref, max_edges=80, medium dataset); cells 1-12 complete, cells 14-24 pending. ETA ~2026-10-02 UTC per heartbeat. Active run verified: /vol/data/benchmark/runs/sweep_013_edges80, source COMEBin-v11-sweep@95f5ea8, medium 3000-contig dataset.
- [x] **Issue triage continuation (2026-09-26)**: new/updated issues #23 (CAMI3 assembly source), #24 (README cleanup), #25 (optimization improvements), #26 (logging improvements); commented without duplicating existing responses
- [x] **Issue triage (2026-09-29T10:45Z)**: issues #29 (small test data floor ~101 contigs), #28 (marker seed graceful degradation), #27 (check-in) — triaged without duplicating existing responses; posted non-duplicating context-aware status updates re: sweep_011_batch512 active run.
- [x] **Issue triage follow-up (2026-09-26)**: added comments to issues #26 (logging), #25 (optimization), #24 (README cleanup), #23 (Cami3 assembly source), #22 (summary table), #21 (seed reproducibility), #20 (optimization candidates), #19 (better plots); all without duplicating existing responses
- [x] **Issue triage follow-up (2026-09-29T13:06Z)**: issues #29, #28, #27 updated; triaged without duplicating existing responses; posted context-aware status updates re: sweep_013_edges80 active run.
- [x] **Agent restart (2026-09-26, second resume)**: verified disk state consistent with first resume; CAMI III rerun complete (492 bins, Zenodo v3:10.5281/zenodo.22973575), no active .active_run; all benchmark runs complete; no unfinished steps remaining; re-triaged open issues #26-#1 without duplicating existing responses; touched .heartbeat, updated .activity and agent-activity.log
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
- [x] **Script modifications committed (2026-09-27)**: `run_comebin_fix.sh` pre-flight free-space guard (≥2 GiB free check to prevent ENOSPC poisoning of CheckM marker tables) and `run_eval.sh` CheckM2 thread-capping/retry guard (≥400 bins → cap at 16 threads, automatic retry at lower thread count on failure). Both guards env-overridable. Committed to main as `170ca0ad`.
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
- [x] **COMPLETE: fix_v11 full-large benchmark + evaluation (2026-09-24/25)** —
      `runs/fix_v11_20260924` registered at 2026-09-24T10:37Z, source COMEBin-v11
      @ `95f5ea8` (branch comebin-optimizations-v11), full demo dataset (29,434
      contigs), 32 threads, seed 42. **exit_code 0, wall_s 24,741 (~6.9 h),
      finished 2026-09-24T17:29:36Z, 71 non-empty bins.** Training stopped
      **early at epoch 184/200** — not an error: upstream v1.1.0
      `run_comebin.sh` passes `--earlystop` (Top-1 > 99 % for 3 consecutive
      epochs: 99.10 → 99.22 → 99.04 %); clustering then ran 120/120 Leiden and
      finished normally. Evaluation (run 2026-09-25 01:04–01:16Z, no other
      run active): **CheckM2** rc 0 / 71 s → 71 bins, 24.38 % mean completeness,
      3.78 % contamination, HQ 1, MQ 6; **CheckM v1** rc 0 / 398 s → 21.62 % /
      5.18 %, HQ 0, MQ 8. Auto-reporting wrote `results/fix_v11_20260924.csv`,
      `runs/fix_v11_20260924/per_bin_results.csv`, `per_bins.png` and refreshed
      both comparison figures. README Current/Next + `docs/11` table/history row
      updated. Versus baseline (same data): +1.7 % wall, 60 → 71 bins,
      −0.63 pp completeness, +0.80 pp contamination.
- [x] **CLOSED: issue #18 "Benchmark size"** (user, 2026-09-24 15:31Z; triaged
      2026-09-25 01:10Z, comment `5824960513`; tiny results `5825479305`; human
      results `5826454210`). Two directives — BOTH MEASURED:
      (a) **smallest functional dataset** — floor FOUND: `tiny_test_n100` FAILS
      (exit 1, 0 bins, HNSW `k = max_edges+1 = 101` > N = 100), `tiny_test_n101`
      PASSES (exit 0, wall 85 s, 1 bin; CheckM2 63.89/9.05 MQ1, CheckM v1
      46.58/6.35; `results/tiny_test_n101.csv`). Floor ≈ 101 contigs.
      (b) **CAMI II human host-associated ~1/6 set** — input BUILT
      (`scripts/prep_cami2_human.sh 4900`: top 4,900 longest GSA contigs of
      `gastrooral/sample_0`, 166,008,681 bp, N50 1,464,728; all 10.6 GB reads
      re-mapped `bwa mem -p -t 32` → `human_sample0_input/bamfiles/human.bam`,
      4.74 GB, md5 `c48e4caa…`) and run **COMPLETE + EVALUATED**:
      `runs/human_v11_20260925` (source COMEBin-v11 `95f5ea8`, seed 42, 32 thr,
      MODE=cami2-human) exit 0, wall 4,912 s (≈ 1.37 h), 200/200 epochs
      (Top-1 ≈ 96 %, no early-stop), **107 bins**; CheckM2 35.31/5.13
      (HQ 20 / MQ 29), CheckM v1 32.64/4.65 (HQ 21 / MQ 29) — first dataset
      with substantial HQ recovery (top bins ≈ 100 % / ≤ 0.45 % under both
      tools). Comment `5826454210`, docs/11 row + per-bin CSV + figures in.
      Next: **CAMI II marine sample_0** — prep **COMPLETE** (2026-09-25
      04:13Z, `prep_cami2_marine.sh 2000`: 41,988 ctgs ≥ 2000 bp → contigs.fa
      md5 f108fb…, marine.bam 4.95 GB + .bai md5 94382c…, ground truth
      `binning_gs_subset.tsv` 41,988 lines; input_meta.txt in place at
      `marine_sample0_input/`). FIX RUN **LAUNCHED 04:14Z**: `runs/marine_v11_20260925`,
      MODE=cami2, source COMEBin-v11 `95f5ea8` (clean), seed 42, 32 thr,
      assembly_contigs=41,988 retained, coverage stage (1 BAM worker) →
      ETA ~9-10 h (≈1.4× demo contig count); per docs/01 marine plan =
      fix-branch run only (same as human precedent, no separate marine
      baseline documented). Then eval via run_eval.sh → report + docs/11 row →
      CAMI III (disk budget ≤ 30 GB, 351 GB free).
- [x] **Issue #7 flowchart "different logic"** (user comment 2026-09-24 11:44Z):
      previous cycle/loop flowchart rendered badly → replaced with a straight
      4-stage pipeline (small → medium → large → keep/revert, no back-edges) in
      README + docs/09, delivery comment posted 2026-09-25 01:39Z, pushed and
      confirmed rendering in place. DONE.
- [x] **Issue #12 subplot request + issue #7 mermaid truncation (2026-09-24 ~11:32 UTC)**:
      `make_per_bin_plots.py` now writes `results/figures/comp_vs_cont_by_dataset.png`
      (one panel per benchmark dataset auto-derived from run_meta.txt `contigs:`;
      runs colored within panel → direct same-dataset comparison) and the README
      Results section embeds it; all-runs scatter + per-run bar charts kept.
      Mermaid flowchart labels shortened (GitHub clips long labels) in README +
      docs/09, full gate rule stays in the bullets below. Commit `53a4b25`;
      replies `5813259715` (#7), `5813260237` (#12).

- [x] **Issues #17/#14/#7/#8 triaged by supervisor (2026-09-24 ~11:07 UTC, re-triaged 2026-09-25)**: #17 — gate
      rule made explicit in README + docs/09: big benchmark runs only after small AND
      medium validation, parameter tuning on small sets first; fix_v11 passed that gate
      (small_test_v4 + medium_v11 before launch). #7 — optimization flowchart rewritten
      with renderer-safe mermaid (no `<br/>`, no emoji in edge labels). #14 — README
      Current/Next + Results refreshed. #8 — Zenodo record 22935025 metadata edited to
      MIT + expanded description (no new version), DOI HTTP 200. Commit `2524e12`:
      auto-reporting wired into `run_eval.sh` (aggregate CSV + per-bin CSV + bar chart +
      comparison scatter on every successful eval), `make_results_csv.py` auto-derives
      dataset/threads from run_meta, `make_per_bin_plots.py` gained `--all`. Additional
      triage 2026-09-25: issues #12 "Improve reporting" — auto-generated plots (per-run
      bar charts, comparison scatter, per-dataset subplots) fully implemented and
      auto-regenerated after every eval; issue #18 "Benchmark size" — CLOSED, smallest
      functional dataset floor at 101 contigs (tiny_test_n101) and CAMI II human
      ~1/6 set benchmarked (107 bins, 35.31% completeness, 4.912 s wall). Both issues
      have new owner comments addressing remaining questions.

- [x] **CAMI II marine sample 0 benchmark run (→ CAMI III)**
  _(COMPLETE: marine_v11_20260925, exit 0, wall_s 31406 (~8.72 h), 152 non-empty bins,
    COMEBin-v11@95f5ea8, cami2 mode, seed 42; finished 2026-09-25T12:58:15Z;
    41,988 contigs ≥ 2000 bp).
    **Evaluation COMPLETE 2026-09-26** (attempt 1 checkm2_rc=1: DIAMOND hit
    "No space left on device" — 12.5 GB of orphaned /tmp intermediates from an
    earlier CAMI III download attempt filled `/`; orphans removed, run_eval.sh
    re-run → checkm2_rc 0 / 356 s, checkm_rc 0 / 998 s).
    CheckM2: 152 bins, 50.60% mean completeness, 4.10% contamination (HQ 35, MQ 60).
    CheckM v1: 152 bins, 46.36% mean completeness, 5.09% contamination (HQ 37, MQ 60)
    — strongest quality of any benchmark dataset so far (demo 25%, human 35%).
    Epoch 159/200 (Top-1 99.31 → 99.58% × 3), Leiden 120/120; early stop via
    run_comebin.sh --earlystop. Reported in docs/11 + README + results CSVs
    (results/marine_v11_20260925.csv, runs/marine_v11_20260925/per_bin_results.csv)._

- [x] **CAMI III toy human gut: prep + benchmark run COMPLETED (2026-09-26)**
      (scripts/prep_cami3_toy.sh created by sibling session; left uncommitted —
      its WIP). Prep input at
      `/vol/data/datasets/cami_III/toy_human_input_2samples/`: `contigs.fa`
      (top-5000-longest of pooled GSA contigs, 1.1 GB), `input_meta.txt`,
      complete bwa index (.amb/.ann/.bwt/.pac/.sa, built 02:17–02:24), and
      both coverage BAMs mapped + indexed + quickcheck OK:
      `bamfiles/sample_0_bam.bam` (76 MB) and `sample_1_bam.bam` (85 MB),
      each with `.bai`. The prep-driving session exited mid-flight after
      sample_0's BAM; remaining steps (sample_0 index, sample_1
      extract+mapping+sort+index, both quickchecks) completed idempotently via
      `finish_prep_cami3.sh` (nothing deleted; the earlier "sample 1 corrupted"
      note was wrong — the long-read archive holds `anonymous_reads.fq.gz`,
      the short-read archive only `reads_mapping.tsv.gz`).
      **Run `cami3_v11_20260926` launched 2026-09-26 02:45 UTC** detached via
      run_comebin_fix.sh: MODE=cami3, seed 42, 32 threads, commit 95f5ea8 /
      comebin-optimizations-v11, registered in `.active_run`, watchdog owns
      handoff. Eval via run_eval.sh afterwards (CheckM2 + CheckM v1 →
      auto-report + Zenodo update).
      *2026-09-26 03:00: made `make_results_csv.py` label the run correctly —
      its `cami3`/`cami2` needles never matched the real `cami_III`/`cami_II`
      contigs paths, so the CAMI III row would have fallen back to a directory
      basename (same gap that made the human/marine rows read
      `human_sample0_input`/`marine_sample0_input`). Matcher now checks
      `cami_III` before `cami_II` (substring!); fix `32c5240` committed +
      deployed atomically to `bin/` so post-eval regeneration labels it
      "CAMI III".*
      *2026-09-26 04:36: **run FAILED** (exit_code 1, wall 6,677 s, 0 bins) —
      not a binning bug: the prep's leftover downloads `/tmp/url_anonymous_reads.fq`
      (9.1 G) + `.fq.gz` (4.7 G) had filled `/` to 100% since 02:42, so
      get_result's `checkm analyze` (bacteria) wrote incomplete marker tables
      (`/tmp` ENOSPC: 21 hmmfetch fatals + 3 dead workers, 04:02–04:04) and
      final selection died `KeyError: '110'`. Verified the reads were already
      staged in the dataset (`logs/sample_{0,1}/…/anonymous_reads.fq.gz`,
      5.0 G + 4.7 G, no process held the /tmp copies) → deleted both, `/`
      100%→28%; removed 68 orphaned hmm temp files (777 M). Watchdog triaged
      at 04:40:01 (terminal marker in run_meta + `.watchdog_terminal`, no
      retry); failed run dir kept untouched as evidence.*
      **Retry `cami3_v11_20260926_rerun` launched 2026-09-26 04:48 UTC**
      (fresh run dir per protocol — the fix wrapper refuses existing dirs):
      MODE=cami3, seed 42, 32 threads, commit 95f5ea8, dirty 0, registered in
      `.active_run` (pid 3727084), watchdog owns handoff. Same deterministic
      pipeline (seed 42 ⇒ same embeddings/kmeans).*
      *2026-09-26 06:18: **retry COMPLETED** — exit 0, wall 5,392 s (90 min),
      full 200/200 epochs (final Top-1 74.95 %, no early stop; epoch 99 loss/top1
      bit-identical to attempt 1 ⇒ deterministic replay), Leiden 120/120 →
      **492 non-empty bins**; run_meta has exit_code/wall_s/bins, `.active_run`
      cleared by cleanup. Eval launched detached 06:18 (run_eval.sh): CheckM v1
      rc 0 (2,514 s incl. pplacer over 492 bins) → **32.46 % / 13.38 %
      (HQ 54, MQ 100)**; CheckM2 attempt 1 rc 1 — CheckM2 1.1.0's 32-thread
      gene-calling race on the 492-bin set ("List of protein files does not
      match internal reference"), failed output preserved as
      `eval/checkm2.incomplete.<ts>`, **16-thread retry rc 0** (1,137 s) →
      **35.97 % / 11.42 % (HQ 53, MQ 112)** — most bins and most HQ/MQ of any
      run, highest mean contamination (strain-rich toy gut). Report chain all
      rc 0: `results/cami3_v11_20260926_rerun.csv` (label **"CAMI III"** via
      the `32c5240` matcher fix), per-bin CSV + plots, combined bar plot (3 main
      datasets unchanged per #12), **Zenodo v3 PUBLISHED** — record 22973575,
      version DOI [10.5281/zenodo.22973575](https://doi.org/10.5281/zenodo.22973575)
      (520 MB tarball, cami3's 492 bins ship as the new data per #8). The
      auto-chain's post-publish step then crashed (zenodo_update.sh assumed the
      API `files` dict shape, record returned a list → `AttributeError`), so the
      agent verified the published file via API (size 520,343,638 + md5
      b8b1b647… match), wrote `meta/zenodo_benchmark_release_v3.json`, advanced
      `meta/zenodo_last_content.sha256` (eea30326…, blocks a duplicate v4) and
      fixed+deployed `scripts/zenodo_update.sh` (files-shape normalised);
      concept DOI already resolves to v3; version DOI showed the known DataCite
      lag (404 at +2 min, v2 took ~68 min → recheck later).
      docs/11 (summary row + two attempt rows) and the README completed-run
      bullet with the v3 DOI committed + pushed `a057f021`; **issue #6 results
      comment posted 2026-09-26 07:56 UTC** (issuecomment-5844421749).
      Version-DOI recheck running detached (poller every 2 min, updates the
      receipt when DataCite propagates).*

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

- [x] **Issue #12 combined bar plot + stats table (2026-09-26, commit `3328a96`)**:
      `scripts/make_combined_bar_plot.py` renders the FAIRyMAGs-style
      `results/figures/combined_bar_plot.png` (+ `.svg`): 2 rows (contamination
      <5% / <10%) × 3 columns, one subplot per main dataset (demo 29,434 /
      human 4,900 / marine 41,988 contigs), bars labelled run + COMEBin commit
      + branch (e.g. `fix_v11_20260924 · 95f5ea8 · comebin-optimizations-v11`).
      Auto-regenerated by `run_eval.sh` after every successful eval; README
      shows the figure with the run stats table
      (`results/main_runs_table.md`) directly underneath. Interpretation of
      "focus only on 3": demo/human/marine; stated in the #12 delivery comment
      so the owner can correct it.

- [x] **Issue #8 Zenodo continuous updates (2026-09-26, commit `3328a96`)**:
      `scripts/zenodo_update.sh` (package → SHA-256 manifest → content-hash
      change detection → new version of concept 10.5281/zenodo.22935024 →
      md5/size + DOI verification → receipt) is wired into `run_eval.sh`
      auto-reporting. **Version 2.0 published** automatically by the marine
      eval: record 22969763 (`comebin_benchmark_release_v2_20260926.tar.gz`,
      168,110,629 B, md5 verified; 7 runs / 410 bins / 522 files; receipt
      `meta/zenodo_benchmark_release_v2.json`). Script hardened for Zenodo's
      async publish (HTTP 202 → poll to state=done) and excludes volatile
      status logs from the change hash.
      *Follow-ups 2026-09-26: version DOI 10.5281/zenodo.22969763 propagation
      resolved (HTTP 200 + DataCite `findable` at 02:54 UTC, ~68 min after
      publish; receipt updated, comment posted on #8). #8 and #12 were closed
      by automation at 02:23 with their own verification comments — including
      commit `34ea532`, which fixed a real deployment gap (the auto-report
      scripts were never installed to `/vol/data/benchmark/bin`, and helpers
      resolved the repo as `dirname(script)/..` = the data dir, not the repo,
      when invoked from `bin/`). Verified after the fix: `bin/run_eval.sh`,
      `bin/zenodo_update.sh`, `bin/make_combined_bar_plot.py` are
      byte-identical to the repo and `REPO` resolution now works — so the
      next evaluation really does regenerate figure + Zenodo version.*

### 2026-09-28 Documentation deliverables (#24/#22/#19/#26)

- **#24 README restructured into sections a–f** exactly as the owner asked:
  a = agent tag (live banner + log links), b = short "what this is / focus only
  on COMEBin, aim to be best binner", c = Progress (one latest-achievement
  bullet + one next-step bullet), d = the 4 benchmark plots (4-dataset combined
  bar plot, rows stacked below each other), e = all-runs table (injected
  between `<!--ALL-RUNS:START/END-->` markers), f = links (Zenodo, COMEBin fork,
  PROGRESS, all runs, major-steps log). Banner lines 1–4 kept heartbeat-owned.
- **#22 all-runs summary table** now generated by
  `scripts/make_all_runs_table.py` → `results/all_runs_table.md` AND auto
  injected into README section e. Columns per owner's spec: run date, duration,
  dataset + public link, COMEBin branch/commit, size (GB, contigs), #bins,
  CheckM2 comp/cont, HQ/MQ, F1, one-line comment. Includes ALL runs — failed
  (small_test, small_test_v2, tiny_test_n100, cami3_v11_20260926,
  baseline_unmodified/baseline_rerun superseded), small/tiny gates, and the
  sibling's in-flight `small_v11_issue28_regression`. 12 data columns on
  purpose so status-heartbeat's 11-col perf-table remap never touches it.
- **#19 plot regenerated**: `make_combined_bar_plot.py` now draws FOUR datasets
  (demo / CAMI II human / CAMI II marine / CAMI III toy gut) with rows = datasets
  **below each other** (4 rows × 2 cutoff cols), every evaluated run per dataset
  labelled with run · commit · branch. `results/figures/combined_bar_plot.png`
  (4235×5536) + SVG + `results/main_runs_table.md` (5 rows incl. cami3).
- **#26 major-steps logging**: `scripts/make_major_steps_log.py` →
  `status/major-steps.log` (all) + `status/major-steps-last10.log` (last 10),
  both linked from README sections a and f. Derived from run_meta + results
  CSVs on disk plus curated milestones (Zenodo v2/v3, #6/#8/#12, #28 fix).
- Sibling session (separate) owns **#28**: fix committed `41606c8` on
  `comebin-optimizations-v11`, regression run `small_v11_issue28_regression`
  finished 12:55 UTC (process gone; run_meta exit 1, no results CSV yet —
  sibling posts #28). `.active_run` still registered — do not overlap.

### 2026-09-28 Documentation deliverables — delivery + #25 plan (same day)

- Committed+pushed `5cc93218`: README a–f restructure, all-runs table
  generator (12-col, heartbeat-safe), 4-dataset plot, major-steps logs.
- Committed+pushed `596a5536`: `docs/13-optimization-sweep-medium.md`
  (24-cell medium grid, seed 42, ranking rule, CAMI II/III human only
  follow-on, AMBER/GT, biobox export), harness param forwarding
  (TEMP/EMB/EMB_COV/BATCH/MAX_EDGES/LEIDEN_WORKERS/HMM_EVALUE), and
  `scripts/export_biobox.sh` (validated on medium_v11_20260924 → 4.1 MB
  binning.tar.gz + bins.fasta.gz + binning_summary.tsv).
- Delivery comments posted (#19, #22, #24, #26, #25 plan; substantive
  replies #20 optimization ideas, #21 seed 42 + RNG gap, #23 CAMI III
  provenance = pooled GSA chain). #23 reposted after a backtick/heredoc
  mishap (~5870399540).
- `.active_run` now holds the sibling's NEW run `small_v11_prepatch_baseline`
  (pid 2159439, src /tmp/opencode/comebin_prepatch) — the #28 regression run
  itself was deregistered by the sibling. Run slot still busy; no new runs
  launched (sweep = plan only until slot free).

### 2026-09-28 #25 sweep LAUNCHED (slot freed)

- Sibling cleared `.active_run` (~13:06Z) and posted the #28 fix delivery
  (`41606c8`, graceful 0-bin + no `Clustering exited status 1`). Run slot free.
- Created two pinned, clean worktrees for the sweep:
  - `COMEBin-v11-sweep` @ `95f5ea8` (reference base = commit behind
    `medium_v11_20260924`; detached, clean)
  - `COMEBin-master904` @ `904f649` (unmodified upstream master; CPU-only, no
    `-d`/`-s` flags in its `run_comebin.sh` → harness guards skip them cleanly,
    exactly matching the original unseeded baseline semantics)
- Harness `run_comebin_fix.sh`: fixed `set -u` bug (a `[ -n "$VAR" ]` on unset
  sweep vars aborted every cell with `TEMP: unbound variable`), added `N_VIEWS`
  forwarding (cells 15/16) + `sweep:` meta line + `n_views:` meta; all gated on
  `grep -q` support checks so older sources run unchanged. Re-synced to repo.
- `scripts/run_sweep_medium.sh` (NEW): 24-cell medium grid driver, detached +
  resumable. Per-cell seed column (cell 24 = seed 7; rest 42), wait-active_clear
  gate (never overlaps a registered run, polls up to WAIT_MAX_S=4 h), RESUME
  branch evals orphaned rc=0 runs with no results CSV, SKIPs non-zero-exit runs
  for manual triage, never overwrites existing run dirs, evals each cell via
  `run_eval.sh` (CheckM2 + CheckM + results CSV + per-bin plots), syncs per-bin
  artifacts into the repo run dir. docs/13 cell 23 replaced `sweep_023_noearly`
  (early-stop is hardcoded, not a CLI flag) with `sweep_023_embcov512_batch512`.
- **Launch state:** cell 1 `sweep_001_ref` (v11-sweep@95f5ea8, seed 42, 8
  threads, 3000 contigs) RUNNING since 13:09Z — `.active_run` pid 2185694,
  `main.py train ... --device cpu --num_threads 8 --seed 42` verified. Driver
  relaunched at 13:11Z is polling wait-active_clear; when cell 1 exits it
  EVALs the orphaned run then proceeds cells 2–24 serially. Sweep log =
  `/vol/data/benchmark/status/sweep_medium.log`. Test artifact `runs/fix_v11`
  (created by an `env -i` harness smoke test) was removed — not a real run
  (`fix_v11_20260924` untouched).

### 2026-09-28 Owner feedback round (13:07–13:12Z): #24 + #19 actioned

- **#24**: owner "cool, remove the a,b,c keep the heading though" → removed the
  `a.`–`f.` letter prefixes from the six README section headings, kept the
  heading text (`## Agent tag`, `## What this project is`, `## Progress`,
  `## Benchmark plots`, `## All runs`, `## Important links`). No scripts
  reference the lettered headings or their anchors; heartbeat commit `e5e77831`
  carried the README change. Delivery comment posted.
- **#19**: owner "make the plot a bit nicer and readable, the text on the y
  axis is too long" → `make_combined_bar_plot.py` now builds compact two-line
  y ticks via `short_label()` (alias table for the old verbose names, strips
  `_v11` + `_YYYYMMDD` suffixes; commit short-hash on line 2 instead of the
  `name · commit · branch` triple), widens the figure (7.4×ncol) and reserves a
  computed left margin (longest label → `left_margin`, capped 0.30) so labels
  are never clipped. Regenerated PNG + SVG + `results/main_runs_table.md`;
  bin copy synced so the next eval auto-regeneration uses it. Delivery comment
  posted.

### 2026-09-30 — #25 sweep COMPLETE (all 24 cells) + ranking delivered

- **All 24 sweep cells finished**: cell 24 (`sweep_024_seed7`, seed 7) completed
  ~00:29Z — exit 0, wall 2797 s, 15 bins, CheckM2 37.37/5.60, CheckM 35.76/7.87.
  23 results CSVs exist (cells 1, 3–24); cell 2 (`sweep_002_master`) is the
  documented stock-master failure (0 bins). Driver logged `RUN_DONE
  sweep_024_seed7 exit=0`; its post-eval Zenodo hook then published **v15**
  (concept 10.5281/zenodo.22935024) and the driver exited. `.active_run` clear.
- **Ranking final** (`results/sweep_rankings.md`, 23 cells): **winner =
  `sweep_004_temp005` (temperature 0.05)** — 13 bins, CheckM2 43.55/6.77,
  F1 59.37 (vs ref 34.22/4.11, F1 50.44; +9.3 pp comp). Runners-up:
  `sweep_023_embcov512_batch512` (43.16/7.52, F1 58.85, 21 min — fast + strong)
  and `sweep_011_batch512` (41.56/6.34, F1 57.57, 25 min). Insight: **batch ≤
  512** is the cheapest strong axis (≈2× faster, +~7 pp comp); **low temp boosts
  completeness the most**. `sweep_024_seed7` (seed 7, 37.37 comp) vs ref
  (seed 42, 34.22) shows the seed-sensitivity issue #21 warned about.
- **Data-integrity fix**: `rank_sweep_medium.py` now reads applied parameters
  from the run_meta `cmd_wrapper:` line (authoritative) — cells 4–6` sweep:`
  meta said `temp=ref` (stale driver version) though `-l 0.05/0.30/0.50` was
  passed and logs confirm `Tau(temperature): 0.05/0.30/0.50`. Cross-check
  reports any disagreement in sweep_rankings.md. Committed `8275ace8` (cells
  13–23 CSVs + ranking tool) and continuing edits.
- `make_all_runs_table.py`: sweep rows now carry one-line comments + correct
  branch labels (`comebin-optimizations-v11 (sweep worktree)` / `master (sweep
  worktree)`); 23 sweep rows injected into README section e.
- docs/13 updated to COMPLETE with per-cell results + winner section.
- **Next**: advance winner (temp=0.05) to CAMI II human + CAMI III toy human,
  AMBER scoring + biobox export per issue #25; prepare Zenodo bundle with
  sweep results + AMBER + biobox + stats; reply on #25 with the ranking.

### 2026-09-29 resume (00:24–01:00Z): sweep relaunched, guard fixes, #28 + #29 answered

- **State on resume**: `TASK_COMPLETE` absent, no live sweep/benchmark process,
- **2026-09-29T11:17Z**: sweep_012_batch2048 now active (8 threads, seed 42, batch=2048, medium dataset); cells 1–11 complete per sweep_medium.log, cell 12 of 24 running; ETA ~2026-10-02 UTC. fd leak and singleton-guard bugs fixed in harness. .heartbeat current; .activity updated; PROGRESS.md sweep state updated.

- **#25 stall root-caused instead of blindly relaunched**: pass 1 (13:07:50Z)
  heartbeat had gone cold. PROGRESS.md read first, per protocol.
- **#25 stall root-caused instead of blindly relaunched**: pass 1 (13:07:50Z)
  aborted *every* cell because `/vol/data/benchmark/bin/run_comebin_fix.sh`
  still carried the unguarded `[ -n "$TEMP" ]` (line 76) → `set -u` death before
  launch; pass 2 completed cell 1, then cells 3–24 died instantly on the
  concurrent-driver `/tmp/benchmark-start.lock` race (all logged `FAIL … rc=0`
  with **no run dir created**, so nothing was falsely marked done).
- **Singleton guard fixed (two bugs)**: `$(pgrep …)` forks a subshell that
  inherits the driver argv → self-match; and a `ps` on a dead transient pid
  makes the assignment return 1, which under `pipefail` + `set -e` killed the
  driver **silently** after one cell. Fix = ancestor/child relatedness walk +
  ≥5 s process age + double probe + `|| true` on every `ps`-based probe.
  `flock` remains the hard mutex; the guards are only the fast path.
  Pushed: `fa69730a`, `55ad99dd`, `57b9cb5d`, `20ca7e39`.
- **Sweep relaunched detached 00:41:12Z**: `run_sweep_medium.sh --from 3`,
  driver pid 2566340, `.active_run` pid 2566376 → `runs/sweep_003_issue28fix`
  (src `COMEBin-v11` @ `41606c8`). Cells 1/2 skipped by design; 22 cells ×
  ~55 min ≈ 20 h, ETA ~2026-09-30 evening UTC. Verified only `sweep_001/002/003`
  run dirs exist → no cell will be wrongly skipped as done. Watchdog owns the
  handoff; agent keeps `.heartbeat` fresh.
- **Cell 1 recorded** — `sweep_001_ref`: rc 0, 2,827 s, **17 bins**, CheckM2
  34.22/4.11 (HQ 0, MQ 2), CheckM 32.00/5.31 → `results/sweep_001_ref.csv`.
- **Cell 2 root cause pinned** — `sweep_002_master` (stock `904f649`, exit 1 @
  108 s): `train_CLmodel.py:46 length_weight.append(lengths[seq_id])` →
  `KeyError: 'BATS_SAMN07137077_METAG-scaffold_22978'`. Measured on its own
  artifacts: `aug0_datacoverage_mean.tsv` = **29,435 lines** (header + the full
  BAM `@SQ` list, incl. scaffold_22978) vs `aug0/sequences_aug0.fasta` =
  **3,000** contigs (scaffold_22978 absent). Upstream enumerates coverage rows
  from the BAM, lengths from the assembly → the issue-#2 producer/consumer
  mismatch on our medium fixture. v11 is structurally immune (`gen_cov.py`
  allocates over the retained assembly contigs and ignores extra `@SQ`), which
  cell 1 confirms empirically. Evidence kept in `runs/sweep_002_master/`.
- **#28 answered** — acknowledged the owner's directive (medium first → merge
  fix + optimization into `master` asap), reported grid state, cell-1 numbers,
  cell-2 root cause and the plan: push `41606c8` → PR into `master` →
  confirmation medium run on merged master → bioconda prep. `41606c8` is still
  **local only** (origin `comebin-optimizations-v11` = `95f5ea8`).
- **#29 answered** — Galaxy IUC fixture measured: 40 contigs × exactly 20,000 bp
  (800 kb, ids `g1k_0…g4k_9`, GC 26.97 %), coordinate-sorted BAM with 40 `@SQ`
  refs **identical** to the FASTA ids, 2,000 reads / 94 mapped, no `.bai`;
  wrapper pins `comebin 1.1.0`, test uses `max_edges=20` (XML help: must be
  < contig count) and `batch=1024`; PR #8351 merged 2026-08-25 with
  `Test tools (0, 3.11): success`. Caveats posted: `MINIMUM_FINAL_BIN_SIZE =
  200000` vs an 800 kb assembly → smoke test only (a 0-bin run is still green),
  and a pre-#28-fix checkout crashes on the empty marker seed. Fixture stored
  at `/vol/data/datasets/galaxy_comebin_fixture/` (md5 `e6b5f3bb…` fasta,
  `373f4411…` bam); end-to-end run on `41606c8` is queued behind the sweep
  (overlap rule).
- **Post-sweep tooling hardened while waiting**: `scripts/rank_sweep_medium.py`
  shipped with a **stray syntax error** (`del par for par in []` in the format
  call) that would have killed the ranking the moment the grid finished —
  removed, plus defensive `as_int`/`as_float`/`fmt_f1` guards (a `-`/empty CSV
  cell no longer raises `ValueError`) and `n_views=6` normalised to `ref` so
  the reference cell shows "reference (defaults)". Verified out-of-tree against
  a synthetic malformed row. `scripts/run_galaxy_fixture_test.sh` (NEW) wraps
  the issue-#29 fixture run: `CONTIGS`/`BAMDIR`/`MODE=galaxy_fixture`,
  `MAX_EDGES=20` (Galaxy's own value; 100 > 40 contigs → `ValueError`),
  `bamfiles/` symlink created, and it inherits the harness's
  no-overlap/no-overwrite guards. Pushed `9d36e82c`, `3ac437d7`.
- **AMBER marine evaluation delivered (01:11Z, #25 follow-on)**: official
  CAMI-standard scoring of `marine_v11_20260925` (152 final bins) against the
  official CAMI II marine gold standard (`binning_gs.tsv` @Version 0.9.1,
  1,475,976 rows). AMBER cloned to `/vol/data/repos/CAMI-AMBER`, env
  `/vol/data/envs/amber` (Python 3.11); prediction regenerable via new
  `scripts/make_amber_prediction.py` and archived as
  `results/amber/marine/comebin_v11_marine.binning`. **RESULTS (bp-weighted)**:
  F1 0.330, precision_avg 0.735 (weighted 0.862), recall_avg 0.213 (weighted
  0.296), ARI 0.844, accuracy 0.294, misclassification 0.138, 34.1 % of bp
  assigned. Full write-up `docs/14-amber-cami2-marine.md`; artifacts in
  `results/amber/marine/` (amber_results.tsv, bin_metrics.tsv,
  amber_report.html, heatmap_bar.png). Human + CAMI III AMBER evals can now be
  one-liners after the sweep winner is chosen.
- **AMBER human evaluation delivered (01:22Z)**: imported the CAMI II human
  gold standard (`setup.tar.gz` 1.9 GB → `gsa_mapping.tsv.gz` filtered to the
  4,900-contig subset, 4,900/4,900 mapped to 64 genomes, AMBER format at
  `/vol/data/datasets/cami_II_human/gold_standard/human_binning_gs.tsv`), scored
  `human_v11_20260925` (107 bins): **F1_bp 0.681**, precision_avg 0.626
  (weighted 0.819), recall_avg 0.747 (weighted 0.722), ARI 0.769, 99.3 % of bp
  assigned. Docs/15 + `results/amber/human/`; docs/01 + docs/13 TODO cleared.
  Side-by-side: marine F1 0.330 (34 % bp assigned) vs human F1 0.681 (99 %).
- **Biobox exports generated** for `marine_v11_20260925` (152), 
  `human_v11_20260925` (107), `medium_v11_20260924` and
  `cami3_v11_20260926_rerun` (492) via `scripts/export_biobox.sh` →
  `runs/<run>/biobox/{<sample>.binning, tree/comebin/v11/binning/<sample>/*.fna,
  binning.tar.gz, binning_summary.tsv, bins.fasta.gz, stats.csv}`.
  Exporter hardened: emits the **authoritative CAMI binning v0.9.1
  `<sample>.binning`** (`@@SEQUENCEID BINID`, the same format AMBER consumes)
  and computes **numeric** contig lengths (was `NA`). New
  `scripts/validate_binning.py` structurally validates the format (upstream
  `bioboxes/validator` is assembler-only and not public). All four validated OK.
  `runs/*/biobox/` is `.gitignore`d (binaries → Zenodo, not git).

### 2026-09-29 #25 sweep repaired + relaunched (01:28–01:37Z)
- **Bug found on resume**: the sweep driver had exited at 01:28:31Z after
  walking cells 3–24. Cell 3's *run* finished fine (`RUN_DONE ... exit=0`,
  17 bins) but every following step failed instantly. Root cause =
  `/tmp/benchmark-start.lock` contention: cell 3's harness (`exec 9>"$START_LOCK"`)
  leaked fd 9 to the COMEBin pipeline's descendants, so the lock was still held
  ~5 s after the harness exited. The in-line `run_eval.sh` (same lock,
  `flock -n`) failed → cell 3 lost its results CSV; cells 4–24 then each failed
  `run_comebin_fix.sh` in <1 s ("another benchmark launch holds ..."), so the
  driver logged `FAIL ... rc=0` (the `!` inverts `$?`) and printed
  `SWEEP COMPLETE (24 cells processed)` with only cells 1 and 3 actually run.
  (The `EMB: unbound variable` line in cell 4's `.comebin.out` is a **stale
  13:07 pre-fix artifact** appended to the same file; the current harness guards
  every sweep var with `${X:-}`.)
- **Fix**: harness now closes fd 9 for its children (`sample_resources ... 9>&-`,
  the `cmd_train_py` subshell `9>&-`, and the COMEBin pipeline
  `... 9>&- 2>&1 | tee ... 9>&-`) so the start-lock cannot outlive the run;
  harness + `run_eval.sh` use **bounded blocking** waits (`flock -w 300` /
  `flock -w 600`) instead of `flock -n`, turning a transient holder into a few
  seconds' wait rather than a hard failure. Deployed to `bin/`.
- **Singleton-guard fix**: the driver's foreign-process scan used
  `pgrep -f run_sweep_medium.sh`, which started matching the **supervisor
  agent's** `opencode` argv (its prompt embeds the diagnostics) → every relaunch
  aborted at 01:33Z. A match now only counts if it is actually executing this
  script (`argv[1]` basename == ours; `_SELF_BASENAME` added).
- **Relaunched 01:35:15Z**: `run_sweep_medium.sh --from 3` (driver pid 2637346)
  → re-evals cell 3 (`sweep_003_issue28fix`, CheckM2/CheckM →
  `results/sweep_003_issue28fix.csv`), then runs cells 4–24 fresh. No
  `runs/sweep_004…24` dirs exist → none will be wrongly skipped. ETA
  ~2026-09-30 evening UTC.

## Watchdog / restart

`scripts/agent-watchdog.sh` (installed at `/vol/data/benchmark/bin/`, cron `*/5 * * * *`):
stale heartbeat (>15 min) → `opencode run` continues session
`ses_f31799c77ffeTq9gcYgqc4hBhg`; if that failed → fresh session with resume prompt.
Both prompts first check GitHub issues for user instructions. On quota/token/context
errors it forces `--model` rotation through the free model list; a successful run
clears the flag (back to default). Rate limit 6 restarts / 6 h; stops when
`TASK_COMPLETE` exists. **Agent: touch `/vol/data/benchmark/.heartbeat` regularly.**

### 2026-09-26 Agent Resume

- Verified all benchmark runs complete: cami3_rerun (492 bins), fix_v11 (71 bins), marine (152 bins), human (107 bins), medium (16 bins)
- No active `.active_run`; no `TASK_COMPLETE` file
- All open issues #26-#1 triaged without duplication (last comment 2026-09-26T14:25:00Z)
- Issues #26 (logging), #25 (optimization), #6 (optimization), #1 (inbox) all previously addressed
- `.heartbeat` touched routinely; status infrastructure intact

### 2026-09-26 Agent Resume (second)

- Verified all runs complete (cami3_rerun 492 bins, fix_v11 71, marine 152, human 107, medium 16), no active .active_run
- All open issues #26-#1 triaged without duplication; PROGRESS.md and .activity synced
- .heartbeat touched; agent-activity.log updated
- Resuming from agent restart with no unfinished benchmark steps (2026-09-26 second resume)

### 2026-09-29 Agent Resume (current)

- Verified disk state: sweep medium grid on COMEBin-v11-sweep@95f5ea8, 24 cells total. Cells 1–23 complete, cell 24 running (sweep_024_seed7, seed=7, temp=ref, emb=ref, emb_cov=ref, batch=ref, max_edges=ref, lw=ref, n_views=6, 8 threads). sweep_024_seed7 started 2026-09-29T23:42:47Z, currently at epoch 91/200; all previous cells exit 0 with eval OK. ETA ~1-2 h remaining for cell 24 to finish training.
- Issues #29 (small test data floor ~101 contigs — floor confirmed at 101 contigs; #28 marker seed generation graceful handle — fix committed locally on optimization branch; #27 operational check) commented without duplication; #26 (logging) and #25 (optimization) previously addressed; issues updated 2026-09-29T13:08Z triaged without duplication
- Sweep cells 1–23 complete (all exit 0, eval OK):
  sweep_001_ref (17 bins, CheckM2 34.22/4.11 HQ 0 MQ 2), sweep_002_master (exit 1, BAM/contig mismatch documented), sweep_003_issue28fix (17 bins, CheckM2 34.22/4.11 HQ 0 MQ 3), sweep_004_temp005 (temp=0.05, 17 bins), sweep_005_temp030 (temp=0.30, 17 bins), sweep_006_temp050 (temp=0.50, 17 bins), sweep_007_emb1024 (15 bins, CheckM2 38.40/4.76 HQ 0 MQ 2), sweep_008_emb4096 (8 bins, CheckM2 rc 0), sweep_009_embcov1024 (16 bins, CheckM2 35.80/4.12 HQ 0 MQ 2), sweep_010_embcov4096 (17 bins, CheckM2 34.33/3.92), sweep_011_batch512 (17 bins, CheckM2 34.33/3.92), sweep_012_batch2048 (17 bins, CheckM2 34.33/3.92), sweep_013_edges80 (15 bins, CheckM2 40.39/5.29 HQ 0 MQ 3), sweep_014_edges150 (18 bins, CheckM2 32.15/3.97), sweep_015_views4 (17 bins, CheckM2 33.84/4.84), sweep_016_views8 (17 bins, CheckM2 34.68/4.56), sweep_017_w4 (17 bins, CheckM2 34.22/4.11 HQ 0 MQ 3), sweep_018_w16 (17 bins, CheckM2 34.22/4.11 HQ 0 MQ 3), sweep_019_eval1e3 (17 bins, CheckM2 34.22/4.11), sweep_020_eval1e7 (17 bins, CheckM2 34.22/4.11), sweep_021_comboA (20 bins, CheckM2 30.30/3.21, temp=0.30 emb=1024 batch=512), sweep_022_comboB (17 bins, CheckM2 34.10/4.22, temp=0.05 emb=4096 batch=2048), sweep_023_embcov512_batch512 (13 bins, CheckM2 43.16/7.52, emb_cov=512 batch=512)
- **Current sweep running**: sweep_024_seed7 running (8 threads, seed=7, temp=ref, emb=ref, emb_cov=ref, batch=ref, max_edges=ref, lw=ref, n_views=6). Cell 24 of 24 running, cells 1–23 complete. CheckM2/CheckM eval to follow after training completes. ETA ~1-2 h remaining per heartbeat.
- .active_run registered: sweep_024_seed7 (pid verified); .heartbeat touched; status infrastructure intact; agent-activity.log updated
- **2026-09-30T00:XXZ**: sweep_024_seed7 active cell 24/24 (seed=7, temp=ref, medium dataset); cells 1-23 complete, cell 24 running epoch N/200; ETA ~1-2 h remaining. .heartbeat current; PROGRESS.md updated.

- [x] **Issue triage (2026-09-29T10:35Z)**: new/updated issues #29 (small test data floor), #28 (marker seed generation), #27 (check-in) — triaged without duplicating existing responses; comment IDs recorded in agent-activity.log.
### 2026-09-30 Agent Resume (01:13–01:17Z) — winner run active, eval chain queued

- `TASK_COMPLETE` absent → continuing. PROGRESS.md read first; disk state verified.
- **Sweep is COMPLETE (24/24)** per the 2026-09-30 section above (winner
  `sweep_004_temp005`, temperature 0.05). `results/sweep_rankings.md` + 23 results
  CSVs + biobox exports for 23/24 cells are on disk; #25 result comment
  `5901812071` already posted 00:43Z.
- **First unfinished step = advance the winner (temp=0.05) to CAMI II human.**
  `runs/human_v11_winner_20260930` is REGISTERED and live: source
  `COMEBin-v11-sweep@95f5ea8` (detached HEAD, clean), seed 42, 32 threads,
  4,900 contigs, `-l 0.05`, started 2026-09-30T00:41:57Z, ~19 s/epoch,
  epoch 65/200 at 01:15Z → training ETA ≈ 02:00Z + Leiden clustering
  (reference `human_v11_20260925` took 4,912 s wall for the full 200 epochs).
  `.active_run` pid 634536 — **do not launch anything that overlaps it.**
- **Follow-on chain launched detached (no overlap):**
  `/vol/data/benchmark/followups/winner_human_20260930.sh <run_dir> [max_wait]`
  (pid 672031, log `/vol/data/benchmark/status/winner_human_chain.log`). It
  (1) waits until `run_meta.txt` carries `exit_code:` AND the wrapper pid is
  released from `.active_run` (8 h cap), (2) runs `bin/run_eval.sh` →
  CheckM2 + CheckM v1 + results CSV + per-bin CSV/plots + Zenodo version,
  (3) AMBER vs the CAMI II human gold standard
  (`make_amber_prediction.py` → `amber.py`, artifacts copied to
  `results/amber/human_winner/`), (4) `export_biobox.sh` (SAMPLE=human_sample0,
  VERSION=v11_temp005) + `validate_binning.py`. Every step is logged and
  non-fatal for the next. **DEDUP guard: `pgrep -f winner_human_20260930.sh`
  before launching it again** (a restart turn must not start a second chain).
- **Issue triage: nothing new to answer.** Open benchmark issues #29 #28 #27 #26
  #25 #23 #22 #21 #20 #6 #1 — every issue's `updatedAt` equals the timestamp of
  the agent's own last comment (#25 00:43:25Z sweep-complete, #29/#28/#27
  13:08:45Z, #26 09-28T13:00:08Z); `paulzierep/COMEBin` has issues disabled
  (`gh` refuses: "repository has disabled issues"). No duplicate comments posted.
- **Next steps once the chain finishes** (next turn, do not overlap):
  1. Read `status/winner_human_chain.log` + `results/human_v11_winner_20260930.csv`
     and compare against `human_v11_20260925` (CheckM2 35.31/5.13, AMBER F1_bp
     0.681) → decide whether temp=0.05 generalises off the medium set.
  2. Launch the CAMI III toy-gut winner run (temp=0.05, `MODE=cami3`, source
     `COMEBin-v11-sweep@95f5ea8`, seed 42, 32 threads) in a **fresh** run dir
     once `.active_run` is clear; reference = `cami3_v11_20260926_rerun`
     (492 bins, CheckM2 35.97/11.42).
  3. Still queued from #29: Galaxy IUC fixture end-to-end run
     (`scripts/run_galaxy_fixture_test.sh`, MAX_EDGES=20, 40×20 kb fixture).
  4. docs/15 (AMBER) + docs/11 + README + `results/sweep_rankings.md` updates
     with the winner numbers, then a #25 comment with the human/CAMI III
     comparison and the Zenodo bundle of sweep + AMBER + biobox artifacts.
