# 06 — Benchmark command lines (every tool run)

Every benchmark run documents its **exact command lines** — in `run_meta.txt` per
run (fields `cmd_wrapper:`, `cmd_train_py:`, `cmd_from_log:`) and as templates in
this file. Parameters/datasets/timings are therefore reproducible end-to-end.

## COMEBin (every binning run)

Wrapper used by the benchmark (baseline + all fix batches on
`comebin-optimizations`):

```bash
THREADS=32 bash /vol/data/repos/metagenomic-binning-benchmark/scripts/run_comebin_baseline.sh \
  /vol/data/benchmark/runs/<run_name>
```

Which internally runs the unmodified pipeline (source commit recorded in
`run_meta.txt`, tree must be clean):

```bash
cd /vol/data/repos/COMEBin/COMEBin
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba \
  CUDA_VISIBLE_DEVICES= /vol/data/tools/bin/micromamba run -p /vol/data/envs/comebin \
  bash run_comebin.sh \
    -a <contigs.fasta> \
    -p <bam_dir> \
    -o <run>/comebin_out \
    -n 6 -t 32
```

Flag map (as `run_comebin.sh` translates them into `main.py train`):

| wrapper flag | meaning | main.py arg |
|---|---|---|
| `-a` | contigs fasta | (input) |
| `-p` | bam directory (`.bam` + `.bam.bai`) | (input) |
| `-o` | output dir | `--output_path <out>/comebin_res` |
| `-n 6` | number of views | `--n_views 6` |
| `-t 32` | threads | `--num_threads 32` |

Actual `main.py` command captured during baseline (also in `run_meta.txt` /
`comebin_run.log`), with defaults the wrapper injects:

```bash
python main.py train --data <out>/data_augmentation \
  --temperature 0.15 --emb_szs_forcov 2048 --batch_size 1024 --emb_szs 2048 \
  --n_views 6 --add_model_for_coverage \
  --output_path <out>/comebin_res \
  --earlystop --addvars --vars_sqrt --num_threads 32
```

Seed-gene step inside the pipeline (FragGeneScan + HMMER against the marker
database) is invoked by COMEBin itself; its command lines are captured from the
run log as `cmd_from_log:` rows.

## CheckM2 (bin quality, every run)

```bash
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba /vol/data/tools/bin/micromamba run \
  -p /vol/data/envs/checkm2 checkm2 predict \
  --threads 32 \
  --input <run>/comebin_out/comebin_res/comebin_res_bins \
  --output-directory <run>/checkm2 \
  -x fasta
```

Reference DB installed once via `checkm2 download` (see `docs/00-setup.md`).

## CheckM v1 (completeness/purity — lineage workflow, every run)

```bash
MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba /vol/data/tools/bin/micromamba run \
  -p /vol/data/envs/checkm checkm lineage_wf \
  -x fasta -t 32 --tmpdir <run>/checkm/tmp \
  <run>/comebin_out/comebin_res/comebin_res_bins <run>/checkm/
```

(CheckM v1.1.3 reference data installed manually from the official archive —
`https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz`
(288,590,617 B, `gzip -t` verified) → extracted to
`/vol/data/benchmark/checkm_ref/`, then `checkm data setRoot /vol/data/benchmark/checkm_ref`
once. `checkm taxon_list` verified the marker data loads.)

## Dataset preparation

DEMO data (COMEBin official test set, unmodified input):

```bash
# BAM index (once)
samtools index -@ 32 /vol/data/datasets/comebin_test_data/bamfiles/SRR5720343.bam
```

Small benchmark dataset (`scripts/make_small_dataset.sh`, GitHub issue #2) —
top-N contigs by length + all reads overlapping them, using real bioinformatics
tools (BioPython to select, `bedtools/samtools` for the reads):

```bash
bash scripts/make_small_dataset.sh [outdir=/vol/data/datasets/comebin_small] [N=300]
```
Roughly: `samtools/seqkit` selection → `bedtools intersect -abam SRR5720343.bam
-b contigs.bed -u > reads.bam` → `samtools index`.

**Small-dataset test run** (correctness check for issue #2; minutes not hours):
`scripts/run_small_test.sh [rundir=runs/small_test] [threads=32]` — same wrapper
bookkeeping (run_meta with cmd lines, comebin_run.log, resources sampler) but on
`/vol/data/datasets/comebin_small/` (`contigs.fa` + `bamfiles/reads.bam`), using
the pristine baseline source. Underlying command:

```bash
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
micromamba run -p /vol/data/envs/comebin bash run_comebin.sh \
  -a /vol/data/datasets/comebin_small/contigs.fa \
  -p /vol/data/datasets/comebin_small/bamfiles \
  -o <rundir>/comebin_out -n 6 -t 32
```

CAMI II assemblies (downloads): see `docs/01-datasets.md` for the Zenodo/GigaDB
records and md5 checksums.

## Convention

- Every run's `run_meta.txt` carries `cmd_wrapper:` (at launch) and
  `cmd_train_py:` (captured ~12 s in, background) + `cmd_from_log:` (at finish).
- Eval runs append `cmd_checkm2:` / `cmd_checkm:` per run.
- The README performance table links each row to its source commit.