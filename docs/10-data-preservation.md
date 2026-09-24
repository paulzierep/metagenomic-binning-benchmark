# 10 — Data preservation and Zenodo release plan

This is the release checklist for newly generated benchmark data (issue #8). It
keeps the repository small while making a deposition reviewable and
reproducible. The watchdogs do not upload data automatically; an owner-approved
Zenodo account/token and a final choice of data license and release contents
are required for each manual or supervisor-operated deposit.

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

## Current status

- The small derived dataset exists locally at `/vol/data/datasets/comebin_small`
  and its real COMEBin/CheckM2/CheckM gate is complete (`small_test_v4`).
- **Production Zenodo record:** [10.5281/zenodo.22935025](https://doi.org/10.5281/zenodo.22935025),
  version 1, CC BY 4.0. The record was checked through a fresh unauthenticated
  `GET /api/records/22935025` (HTTP 200), and both uploaded file sizes and MD5
  checksums match the local release. A later owner comment requested MIT and
  expanded metadata; because that would change a published version's terms,
  it is being handled as an explicit versioning decision rather than silently
  changing version 1.
- Uploaded files: `comebin_small_release_v1.tar.gz` (95,216,539 bytes,
  SHA-256 `0c698d208639f4fadd4ac4477a67074320c975528b23dd61743c83ad1658b6d2`)
  and `comebin_small.release.public.json` (3,650 bytes, SHA-256
  `84131ae359d07a78db7ae7ca2005758f4f0ec9df67a33ec62f8af50ac1702f1b`).
  The archive extraction and all 18 public-manifest entries were independently
  verified; the token remains only in the mode-0600 local secret file.
- The medium derivative is built and verified locally; its timed COMEBin run is
  registered separately and must not overlap another benchmark. Future releases
  repeat this manifest, license, provenance, and DOI-verification checklist.
