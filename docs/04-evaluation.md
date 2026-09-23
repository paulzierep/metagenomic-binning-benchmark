# 04 — Evaluation (CheckM2 + CheckM)

Both tools score each bin's **completeness** and **contamination** from universal
marker genes. We report both for every benchmark run (user requirement), plus derived
counts of medium/high-quality bins (MIMAG):

- **HQ**: completeness >90 %, contamination <5 %
- **MQ**: completeness ≥50 %, contamination <10 %
- also report the classic set: #bins with (comp>50,cont<10), (70,10), (90,10),
  (50,5), (70,5), (90,5) and the sums — matches COMEBin's own `estimate_res.txt`.

## Environments

```bash
export MAMBA_ROOT_PREFIX=/vol/data/envs/.mamba
# CheckM2
/vol/data/tools/bin/micromamba create -y -p /vol/data/envs/checkm2 -c conda-forge -c bioconda checkm2
# CheckM v1
/vol/data/tools/bin/micromamba create -y -p /vol/data/envs/checkm -c conda-forge -c bioconda checkm-genome=1.1.3 pplacer
```

First run downloads reference data (`checkm2 download`, CheckM data dir) — record
versions + data hashes here when fetched.

## Commands (run via `scripts/run_eval.sh <bins_dir> <out_prefix>`)

```bash
# CheckM2
checkm2 predict --threads 32 --input <bins_dir> --output-directory <out>/checkm2

# CheckM v1 (needs prodigal+hmm+pplacer in env; bins as .fa/.fna)
checkm lineage_wf -t 32 -f <out>/checkm.tsv --tab_table <bins_dir> <out>/checkm_out
```

## Output tables

`results/<run>.csv` columns:

```
run,source_commit,dataset,threads,total_time_s,n_bins,
checkm2_mean_completeness,checkm2_mean_contamination,
checkm2_HQ,checkm2_MQ,
checkm_mean_completeness,checkm_mean_contamination,
checkm_HQ,checkm_MQ,
...
```

Raw tool outputs stay in `/vol/data/benchmark/runs/<run>/eval/` (not committed).

Per-run CSV: `scripts/make_results_csv.py <rundir> [dataset] [threads]` writes the
committed `results/<run>.csv` row (means + HQ/MQ counts, MIMAG thresholds above)
from `run_meta.txt` + the two eval tables. `scripts/run_eval.sh` calls
`parse_eval.py` (appends means to run_meta); then run `make_results_csv.py`.
