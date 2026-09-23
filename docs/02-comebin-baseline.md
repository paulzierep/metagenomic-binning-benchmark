# 02 — COMEBin baseline run (unmodified)

Status: **NOT RUN YET** — env deps finishing; run next, then fill in every field.

## Source (pristine upstream)

```bash
git clone https://github.com/paulzierep/COMEBin.git /vol/data/repos/COMEBin
# record exact commit when running:
git -C /vol/data/repos/COMEBin rev-parse HEAD   # ← paste into the table below
```

## Command

Wrapper: `scripts/run_comebin_baseline.sh` (calls the upstream entry point unchanged):

```bash
cd /vol/data/repos/COMEBin/COMEBin            # cwd matters: ../auxiliary is resolved via $PWD
CUDA_VISIBLE_DEVICES= bash run_comebin.sh \
  -a /vol/data/datasets/comebin_test_data/BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta \
  -p /vol/data/datasets/comebin_test_data/bamfiles \
  -o /vol/data/benchmark/runs/baseline_unmodified/comebin_out \
  -n 6 \          # views (default)
  -t 32 \         # threads (host has 32 cores; upstream README example used 40)
  # -l (temperature): left unset → auto: 0.07 if N50>10k else 0.15 (computed by script)
  # -e 2048, -c 2048, -b 1024 : defaults, unchanged
```

Run inside env:

```bash
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
/vol/data/tools/bin/micromamba run -p /vol/data/envs/comebin bash run_comebin.sh ...
```

## Parameters (baseline defaults)

| Parameter | Flag | Value | Meaning |
|---|---|---|---|
| views | `-n` | 6 | contrastive views (orig + 5 augmentations) |
| threads | `-t` | 32 | bedtools/kmer/leiden/Leiden-pool/CPU-torch threads |
| temperature | `-l` | auto (0.07 / 0.15) | InfoNCE temperature τ, from assembly N50 |
| combine emb | `-e` | 2048 | hidden size, combine network |
| coverage emb | `-c` | 2048 | hidden size, coverage network |
| batch size | `-b` | 1024 | capped to #contigs if smaller |
| contig cutoff | (implicit) | ≥1000 bp | train & cluster filter |
| epochs | (implicit) | 200 max, earlystop ≥10 epochs with top1>99 for 3 | |

Internal steps timed individually (fill from `logs/`):
augmentation (fasta+kmer) → coverage (bedtools) → variance → seed genes
(FragGeneScan+HMMER) → training → HNSW+kNN → 120× Leiden grid → best-bin selection
(unitem/checkm profile) → bin export.

## Results — fill in after the run

| Field | Value |
|---|---|
| Date | |
| Commit | |
| Wall-clock total | |
| per-stage timings | |
| Peak RAM | |
| #bins produced | |
| bins ≥200 kb (filter) | |

See `results/` for the CheckM2/CheckM tables of this run.
