# 10 — Data preservation and Zenodo release plan

This is the release checklist for newly generated benchmark data (issue #8). It
keeps the repository small while making a deposition reviewable and
reproducible. Uploads are **automatic**: after every successful evaluation,
`run_eval.sh` calls `scripts/zenodo_update.sh` (best-effort), which packages the
new data, detects content changes and publishes a new version of the record —
the first automatic update shipped as version 2.0 (see the "Continuous updates"
section below). An owner-approved Zenodo token (mode-0600 `~/.zenodo_token`) and
the chosen license are configured once; the token never leaves the VM.

## What would be released

The preferred release unit is a reproducible derivative dataset, not the VM's
whole working directory:

- `comebin_small` and, after its end-to-end run passes, `comebin_medium`:
  contigs, selected-read BAM, indexes, provenance, and the release manifest;
- selected CAMI II samples when their licensing, storage cost, and provenance
  have been reviewed;
- result tables and the exact COMEBin commit/parameters needed to regenerate
  them.

Raw source archives, temporary extraction directories, model checkpoints, and
large intermediate augmentation files remain local unless explicitly selected
for a release. CheckM databases and environment trees are not uploaded as part
of a dataset record; their versions and checksums are documented instead.

## What is needed before upload

1. **Owner approval and account access:** a Zenodo account with permission to
   create a deposition (normally an owner or authorized account), and a token
   supplied through a secret environment variable or secret store. Never put a
   token in this Git repository, a log, a command transcript, or an issue.
2. **Deposit metadata:** title, authors/creators and ORCIDs where available,
   abstract, keywords, related DOI/repository URL, and a citation suggestion.
3. **Licensing:** an explicit data license (for example CC BY 4.0 when
   appropriate), plus the code license and any third-party restrictions. CAMI
   terms and any human-host-associated restrictions must be checked before
   redistribution.
4. **Release contents and size:** confirm which samples/files are in scope,
   whether raw reads are included, and the expected compressed size. The current
   disk plan keeps the small set permanently and caps the derived medium set at
   5 GB; future human/CAMI additions are budgeted separately.
5. **Provenance:** source URLs/DOIs and checksums, generation commands, source
   repository commit, environment/tool versions, parameters, and the manifest
   SHA-256.

## Manifest first

Generate a manifest outside the dataset directory. It streams SHA-256 hashes and
records every regular file, so the file can be reviewed before upload:

```bash
python3 scripts/make_release_manifest.py \
  /vol/data/datasets/comebin_small \
  /vol/data/benchmark/meta/release_manifests/comebin_small.json \
  --metadata source_commit=<comebin-commit> \
  --metadata dataset=comebin_small
```

For a public copy, add `--omit-local-path` so the VM-specific `dataset_path`
field is not exposed. The JSON contains sorted relative paths, byte sizes, and
SHA-256 values. Add `--exclude` for intentionally omitted files, and use
`--force` only when replacing a manifest deliberately. Keep the manifest and
its own checksum with the release metadata. The same procedure applies to
`comebin_medium` and any CAMI sample selected for publication.

Before depositing, verify that:

- the manifest has no absolute source paths in the public metadata (the local
  `dataset_path` field should be removed or rewritten in the public copy);
- every selected file is present and readable after extraction from a clean
  temporary directory;
- BAM/FASTA indexes and checksums are included where required;
- no credentials, personal data, or unreviewed third-party material are present;
- the repository documentation names the Zenodo DOI and release version.

## Deposit and verification

After owner approval, create a **new version** rather than overwriting a prior
record. Upload the selected archive/files and the public manifest/provenance,
wait for Zenodo's checksum processing, and verify the returned record and DOI
with a fresh unauthenticated request. Save the DOI, deposition URL, version,
uploaded filenames, and final checksums in:

- `docs/01-datasets.md` (dataset provenance and citation);
- the relevant issue comment;
- `results/` or `status/meta/` only as small text/CSV artifacts, never as a
  substitute for the DOI.

If the upload is incomplete or verification fails, retain the local data and
report the failure; do not claim that preservation is complete.

## Continuous updates — `scripts/zenodo_update.sh` (issue #8)

Owner requirement (2026-09-25): *store all benchmark data in the same record,
update continously when new benchmark data is made* — restricted (09:04) to
data that is **newly generated and not publicly available otherwise**.
`scripts/zenodo_update.sh` implements this end to end:

1. **Package** the newly generated benchmark data into a staging directory:
   `results/` (aggregate CSVs + all figures), the `runs/` mirrors
   (`run_meta.txt`, `comebin_run.log`, `per_bin_results.csv`,
   `per_bins.png`), every run's bin FASTAs
   (`comebin_res/comebin_res_bins/`, symlinks dereferenced, non-empty only),
   the key evaluation reports (CheckM2 `quality_report.tsv`, CheckM v1
   `bin_stats_ext.tsv` + `checkm.log`), `docs/`, `README.md`, `PROGRESS.md`
   and `status/agent-activity.log`. Runs without bins and without evaluation
   results are excluded.
2. **Manifest** with `make_release_manifest.py --omit-local-path` (sorted
   relative paths, byte sizes, SHA-256, provenance metadata); the manifest
   ships inside the tarball as `manifest.json`.
3. **Change detection**: SHA-256 over the manifest's per-file hashes is
   compared with `meta/zenodo_last_content.sha256`; identical content exits
   without touching Zenodo, so repeated evaluations cannot create empty
   versions.
4. **Publish as a new version** of record `22935025` under concept DOI
   10.5281/zenodo.22935024: reuse an open draft or `POST .../actions/newversion`,
   upload through the record's file bucket
   (`PUT /api/files/<bucket>/<name>`), refresh title/description/version
   metadata, publish. The concept DOI always resolves to the newest version;
   the per-version DOI of v1 (10.5281/zenodo.22935025) stays valid.
5. **Verify + record**: published file size and MD5 must match the local
   tarball and the DOI resolver is checked; a receipt is written to
   `meta/zenodo_benchmark_release_v<N>.json` and only then is the content
   marker updated.

`run_eval.sh` calls the script best-effort in its auto-reporting block after
**every successful evaluation**, so each newly evaluated run lands in the
record without manual steps. `ZENODO_UPDATE=0` disables it,
`--dry-run` packages everything without any network call, and a missing token
file is a silent skip (the token itself lives only in the mode-0600
`~/.zenodo_token`; never commit or log it).

## Current status

- The small derived dataset exists locally at `/vol/data/datasets/comebin_small`
  and its real COMEBin/CheckM2/CheckM gate is complete (`small_test_v4`).
- **Production Zenodo record:** [10.5281/zenodo.22935025](https://doi.org/10.5281/zenodo.22935025),
  version 1, **MIT** since 2026-09-24. The owner asked for MIT plus a much
  richer description (what the benchmark is used for, how to run, project
  links); Zenodo allows license edits as plain metadata, so the record was
  edited in place and re-published **without creating a new version** (still
  1.0). The public record was re-checked through a fresh unauthenticated
  `GET /api/records/22935025` (HTTP 200, license `mit-license`, expanded
  description live) and both uploaded file sizes and MD5 checksums match the
  local release; the DOI resolver check now returns HTTP 200.
- Uploaded files: `comebin_small_release_v1.tar.gz` (95,216,539 bytes,
  SHA-256 `0c698d208639f4fadd4ac4477a67074320c975528b23dd61743c83ad1658b6d2`)
  and `comebin_small.release.public.json` (3,650 bytes, SHA-256
  `84131ae359d07a78db7ae7ca2005758f4f0ec9df67a33ec62f8af50ac1702f1b`).
  The archive extraction and all 18 public-manifest entries were independently
  verified; the token remains only in the mode-0600 local secret file.
- The medium derivative is built and verified locally (3,000 contigs,
  421,631,278 bytes; `PROVENANCE.txt` and MD5s recorded). Its timed v1.1.0 run
  `medium_v11_20260924` completed with 16 bins and verified CheckM2/CheckM
  results; the parsed row is
  [`results/medium_v11_20260924.csv`](../results/medium_v11_20260924.csv).
  It is not deposited separately until the owner confirms the release license
  and metadata. Future releases repeat this manifest, license, provenance, and
  DOI-verification checklist.
- **Version 2.0 published 2026-09-26** (record
  [10.5281/zenodo.22969763](https://doi.org/10.5281/zenodo.22969763), same
  concept 10.5281/zenodo.22935024 — the first automatic update from
  `run_eval.sh`): `comebin_benchmark_release_v2_20260926.tar.gz`
  (168,110,629 bytes, MD5 `114459d4e728e70b2aefb70e1d8f620e`) with **all**
  seven evaluated runs' bin FASTAs (410 bins), per-bin + aggregate
  CheckM2/CheckM v1 metrics, eval reports, run logs, all figures (incl. the
  combined bar plot), docs and a SHA-256 `manifest.json`; v1 files carried
  over. Published file size + MD5 re-verified against the public record;
  concept DOI already resolves to v2. Receipt:
  `/vol/data/benchmark/meta/zenodo_benchmark_release_v2.json`.
  Derived input subsets (medium/human/marine) are staged as the following
  versions if the owner wants them archived too.
