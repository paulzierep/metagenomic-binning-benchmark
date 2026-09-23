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

### Small derived test set (GitHub issue #2)

`scripts/make_small_dataset.sh` builds a tiny but real benchmark input from the
demo data: **top-300 contigs by length** (3.56 Mbp; longest contigs carry the
marker genes COMEBin needs for its seed-gene step) + **all reads overlapping
them** (real alignment via `bedtools intersect`, not simulated) →
`/vol/data/datasets/comebin_small/` (94 MB). Purpose: fast iteration for fix
batches (a run is minutes, not hours) while keeping COMEBin's real pipeline
logic. Build and usage are documented in `scripts/` + `docs/06-benchmark-commands.md`.

## 2. CAMI II challenge data

| | |
|---|---|
| Source | CAMI II challenge (2021), assembly records on Zenodo |
| Assemblies record | https://doi.org/10.5281/zenodo.5013479 |
| Fraction used first | **marine** (`marine.zip`) |
| marine.zip | 9,424,563,556 B — md5 `1c054a45f83f6475d50198274823886f` ✅ verified |
| Download / extract | `/vol/data/datasets/cami_II/marine.zip` → `cami_II/marine/` |
| Short reads (marine) | https://frl.publisso.de/data/frl:6425521/marine/ (challenge download page) |

Other fractions in the same record: `plant_associated.zip` (3.9 GB),
`strain_madness.zip` (1.9 GB). TODO on first use: confirm exact archive layout
(contigs per sample, ground-truth bins), pick samples, and record how contigs +
coverage input are prepared for COMEBin (per-sample BAMs).

**Marine reads + per-sample inputs** (https://frl.publisso.de/data/frl:6425521/marine/):

| Path | Size (approx) | Use |
|---|---|---|
| `short_read/marmgCAMI2_sample_N_{reads,bam,contigs}.tar.gz` | reads 5.2 G, bam 4.6–4.7 G, contigs 360–436 M | COMEBin input (bam = coverage; contigs = assembly) |
| `long_read/marmgCAMI2_sample_N_{reads,bam,contigs}.tar.gz` | bam 5.9 G, reads 4.4 G, contigs 315–380 M | same, long-read mode |
| `hybrid/*` | 11 G/sample, pooled 106 G | too big for now |
| `marmgCAMI2_genomes.tar.gz` | 798 M | gold-standard reference genomes |

Sample 0 (short-read) contigs+BAM pre-downloaded → `/vol/data/datasets/cami_II/marine_reads/`
(2026-09-23; md5 `412b657ec10dda4d6510aaf39f0236f8` (contigs) / `1de385b6641a32b1acd0806f638d7aa6`
(bam), `gzip -t` OK). **BAMs are supplied pre-mapped** — no read alignment step
needed for COMEBin input (reads `_reads.tar.gz` 5.2 GB/sample NOT required).

**Marine structure — observed (sample 0, short-read):**
- `contigs/`: `anonymous_gsa.fasta.gz` (= pooled ground-truth contigs, names `S0C0…`),
  `binning_gs.tsv` (ground truth bin→contig), `gsa_mapping.tsv.gz` (name map)
- `bam/`: **590 per-genome BAMs** (4.7 G total; `Otu*.bam`, `RNODE_*`; each mapped to its
  own genome assembly contigs `NODE_*`) + `.bai`
- → COMEBin needs ONE coverage BAM over ONE contig set; per-genome BAMs do **not**
  merge directly (duplicate `NODE_*` names across genomes). TODO at CAMI II phase:
  pick contig set (pooled assembly from `marine/pooled/short/*.fasta`, or gsa contigs)
  and map the sample reads (`short_read/.../reads.tar.gz`) to it (`bwa mem`, post-baseline,
  CPU-bound) to build the coverage input.

## 3. CAMI III challenge data (planned)

TODO — same fields as above.
