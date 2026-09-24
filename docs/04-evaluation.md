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
# CheckM v1 (the runner defaults to the Python-3.10 COMEBin environment; the
# standalone checkm environment currently has a Python-3.14/forkserver incompatibility)
CHECKM_ENV=/vol/data/envs/comebin
CHECKM_LD_LIBRARY_PATH=/vol/data/envs/checkm/lib:/vol/data/envs/comebin/lib
```

`run_eval.sh` uses the CheckM v1 installation in `/vol/data/envs/comebin` by
 default because it runs on Python 3.10; it adds the standalone environment's
`libopenblas` directory for `pplacer`. Set `CHECKM_ENV` and
`CHECKM_LD_LIBRARY_PATH` to override this. COMEBin can expose the bin directory
as a symlink, so the runner follows that link when counting non-empty bins and
refuses a zero-bin success before invoking either evaluator.

First run downloads reference data (`checkm2 download`, CheckM data dir) — record
versions + data hashes here when fetched.

## Commands (run via `scripts/run_eval.sh <rundir> [threads]`)

```bash
# CheckM2
checkm2 predict --threads 32 --input <bins_dir> --output-directory <out>/checkm2 -x fa

# CheckM v1 (needs prodigal+hmm+pplacer in env; bins as .fa/.fna)
LD_LIBRARY_PATH=/vol/data/envs/checkm/lib:/vol/data/envs/comebin/lib \
  micromamba run -p /vol/data/envs/comebin checkm lineage_wf -x fa -t 32 \
  <bins_dir> <out>/checkm_out
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
For the medium gate, `medium_v11_20260924_checkm2_stats.csv` supplements the
aggregate row with one CheckM2 record per bin; raw per-bin tables remain under
`/vol/data/benchmark/runs/medium_v11_20260924/eval/`.
