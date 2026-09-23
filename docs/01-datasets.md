# 01 — Datasets

## 1. COMEBin demo data (used first)

| | |
|---|---|
| Origin | Google Drive link in the [COMEBin README](https://github.com/paulzierep/COMEBin), file id `1xWpN2z8JTaAzWW4TcOl0Lr4Y_x--Fs5s` |
| Downloaded | 2026-09-23, 5,575,256,185 bytes → `/vol/data/datasets/comebin_test_data.zip` |
| Extracted | `/vol/data/datasets/comebin_test_data/` (6.4 GB) |
| Sample | BATS `SAMN07137077_METAG` (Sequencing Read Archive `SRR5720343`) |

Files:

| File | Size | Notes |
|---|---|---|
| `BATS_SAMN07137077_METAG.scaffolds.min500.fasta.f1k.fasta` | 53 MB | **29,434 contigs** (≥1 kb subset, "f1k") |
| `bamfiles/SRR5720343.bam` | 5.07 GB | reads mapped to the contigs — COMEBin coverage input |
| `excepted_output/` | — | upstream reference output incl. CheckM results → sanity-check target |

Notes:
- Single sample ⇒ single coverage column; COMEBin demo command uses `-n 6 -t 40`.
- No read-level ground truth shipped; quality is assessed with CheckM2/CheckM
  (marker-gene completeness/contamination) — the metrics this benchmark records.
- Verify/refresh BAM index before use: `samtools index SRR5720343.bam` if `.bai` missing.

## 2. CAMI II challenge data (planned)

TODO — record: URL(s), file names, sizes, checksums, sample(s), which CAMI II
fraction used (e.g. marine/soil/host-associated), truth files if any, and how
contigs/BAMs are prepared for COMEBin.

## 3. CAMI III challenge data (planned)

TODO — same fields as above.
