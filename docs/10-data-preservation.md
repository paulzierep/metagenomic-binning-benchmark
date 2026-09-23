# 10 — Data preservation and Zenodo release plan

This is the release checklist for newly generated benchmark data (issue #8). It
keeps the repository small while making a deposition reviewable and
reproducible. **No Zenodo upload is performed by this document or by the
watchdogs.** An upload requires an owner-approved Zenodo account/token and a
final choice of data license and release contents.

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

The JSON contains sorted relative paths, byte sizes, and SHA-256 values. Add
`--exclude` for intentionally omitted files, and use `--force` only when
replacing a manifest deliberately. Keep the manifest and its own checksum with
the release metadata. The same procedure applies to `comebin_medium` and any
CAMI sample selected for publication.

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

## Current status

- The small derived dataset exists locally at `/vol/data/datasets/comebin_small`
  (real demo contigs and overlapping reads; the end-to-end benchmark is still
  gated behind the active baseline).
- The medium dataset is intentionally not built while the baseline is active.
- A manifest can be generated now, but issue #8 remains open until a Zenodo
  record is created, its DOI is verified, and the README/dataset documentation
  points to that record.
