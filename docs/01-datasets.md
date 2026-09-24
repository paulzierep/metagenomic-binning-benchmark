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
demo data: **top-N contigs by length** (default 300; 3.56 Mbp, with longest
contigs most likely to carry marker genes) + **all reads overlapping them**
(real alignments, not simulated) → `/vol/data/datasets/comebin_small/`
(94 MB). The existing set was originally extracted with `bedtools intersect`;
the committed reconstruction uses indexed `samtools view -L`, which is faster
and deterministic for a contig-name list. Purpose: fast iteration for fix
batches while keeping COMEBin's real pipeline logic.

The next gate is a **medium** derivative (initially N=3,000, hard cap 5 GB),
built only after the small COMEBin+CheckM run succeeds. Commands and the
space plan are in `docs/06-benchmark-commands.md` and
`docs/08-dataset-space-plan.md`. Before any public release, follow the checksum,
licensing, and Zenodo verification checklist in
[`docs/10-data-preservation.md`](10-data-preservation.md).

### Published small release (Zenodo)

The owner-approved small release is published as **[10.5281/zenodo.22935025](https://doi.org/10.5281/zenodo.22935025)**
(version 1, CC BY 4.0). The record contains the verified
`comebin_small_release_v1.tar.gz` (95,216,539 bytes,
SHA-256 `0c698d208639f4fadd4ac4477a67074320c975528b23dd61743c83ad1658b6d2`)
and `comebin_small.release.public.json` (3,650 bytes,
SHA-256 `84131ae359d07a78db7ae7ca2005758f4f0ec9df67a33ec62f8af50ac1702f1b`).
The archive contains 18 payload files totaling 98,078,536 bytes; extraction
and every public-manifest size/SHA-256 check passed. The public record was
verified with a fresh unauthenticated API request (HTTP 200), and the safe
publication record is stored outside the repository at
`/vol/data/benchmark/meta/zenodo_comebin_small.json`.

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
(bam), `gzip -t` OK). Reads archive `marmgCAMI2_sample_0_reads.tar.gz` (5.2 G) also
downloaded + extracted (2026-09-23) → `reads_0/.../reads/`.

**Marine structure — observed (sample 0, short-read):**
- `contigs/`: `anonymous_gsa.fasta.gz` (= pooled ground-truth contigs, names `S0C0…`,
  **1,475,972 contigs / 909 Mbp**), `binning_gs.tsv` (ground truth `S0C* → Otu genome`),
  `gsa_mapping.tsv.gz` (name map)
- `reads/`: `anonymous_reads.fq.gz` — single pooled **interleaved paired-end** file
  (`@S0R0/1`+`@S0R0/2`, 35.25 M reads ≈ 17.6 M pairs); `reads_mapping.tsv.gz` maps
  reads → **genome** (`Otu*`), NOT to contigs
- `bam/`: **590 per-genome BAMs** (4.7 G total; `Otu*.bam`, `RNODE_*`; each mapped to its
  own genome assembly contigs `NODE_*`) + `.bai`

**Input decision (2026-09-23, docs 01+06):** COMEBin needs ONE coverage BAM over ONE
contig set; per-genome BAMs do **not** merge (duplicate `NODE_*` names). Both native
contig sets are far too large for COMEBin training (gsa 1.48 M contigs, pooled Megahit
1.69 M). Chosen approach (matches issue-#2 small-data methodology, real CAMI data):
- contigs = `anonymous_gsa.fasta.gz` **subset to ≥ 2000 bp** → **41,988 contigs**
  (≥1 kbp: 124,436 · ≥2 kbp: 41,988 · ≥5 kbp: 11,605)
- reads = all `anonymous_reads.fq.gz` → `bwa mem -p -t 32` (interleaved) → single BAM
  (reads of unkept contigs produce no alignment; `S0C*` names preserved)
- ground truth = `binning_gs.tsv` subset to kept contigs → direct recall/ARI eval
- prep: `scripts/prep_cami2_marine.sh` (bwa index/mem + samtools sort/index + input_meta)
- run: `scripts/run_comebin_fix.sh` with `CONTIGS=…/marine_sample0_input/contigs.fa`,
  `BAMDIR=…/bamfiles`, `MODE=cami2`, `SRC_COMEBIN=/vol/data/repos/COMEBin-v11`
  (v1.1.0, `-d cpu`, `-s 42`)

## 3. CAMI III challenge data (planned)

TODO — same fields as above.
