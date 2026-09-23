# Per-run detailed logs

Every benchmark run mirrors its **detailed logs** into this directory on
GitHub (`runs/<run>/`), synced by `scripts/status-heartbeat.sh` every 10 minutes
and again at run end. Only small log files are committed; the heavyweight COMEBin
artifacts (augmented data, kmer tables, trained models, tensorboard events, bins)
stay on disk under `/vol/data/benchmark/runs/<run>/`.

Per-run files here:

| File | Content |
|---|---|
| `run_meta.txt` | date, source commit, threads, dataset, exit code, wall time |
| `comebin_run.log` | full stdout+stderr of `run_comebin.sh` — every stage + epoch bars |
| `logs/resources.tsv` | per-30s sampler: CPU %, RSS (GB), system mem used |
| `comebin_res/comebin.log` | COMEBin internal logger (stage timestamps) |
| `comebin_res/training.log` | per-epoch loss / Top1 accuracy |
| `comebin_res/config.yml` | exact training config used |

Full docs: `docs/00-setup.md` (setup + logging), `docs/01-datasets.md`,
`docs/03-fixes.md` (fix batches), `docs/05-agent-restart.md` (watchdogs).