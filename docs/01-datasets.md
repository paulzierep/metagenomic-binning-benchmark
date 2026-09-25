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
(version 1, **MIT** since 2026-09-24 — the record metadata was edited in
place, no new version; the DOI resolves HTTP 200). The record contains the verified
`comebin_small_release_v1.tar.gz` (95,216,539 bytes,
SHA-256 `0c698d208639f4fadd4ac4477a67074320c975528b23dd61743c83ad1658b6d2`)
and `comebin_small.release.public.json` (3,650 bytes,
SHA-256 `84131ae359d07a78db7ae7ca2005758f4f0ec9df67a33ec62f8af50ac1702f1b`).
The archive contains 18 payload files totaling 98,078,536 bytes; extraction
and every public-manifest size/SHA-256 check passed. The public record was
verified with a fresh unauthenticated API request (HTTP 200), and the safe
publication record is stored outside the repository at
`/vol/data/benchmark/meta/zenodo_comebin_small.json`.

### Medium derived test set (local benchmark input)

`/vol/data/datasets/comebin_medium/` contains the top 3,000 contigs by length
from the same BATS demo assembly plus all reads overlapping those contigs. The
verified derivative is **421,631,278 bytes**; `PROVENANCE.txt` records the source
paths, 3,000-contig count, and MD5 checksums:

- `contigs.fa`: `8e6174913ed7db4eb6f05259bae833cc`
- `bamfiles/reads.bam`: `fe31efbae1d07037a54cbe907f47bc1b`

The v1.1.0 benchmark `medium_v11_20260924` completed 200/200 epochs and produced
16 non-empty bins. CheckM2/CheckM v1 results are in
[`results/medium_v11_20260924.csv`](../results/medium_v11_20260924.csv); the
medium release is not deposited separately until the owner confirms its license
and metadata.

### Tiny derived test set — issue #18 "smallest still possible" (2026-09-25)

Two candidate "smallest" datasets were built with the same real-data method
(`scripts/make_small_dataset.sh <out> <N>`, top-N longest demo contigs + the
overlapping reads), because the floor is set by a **hard limit in COMEBin's
clustering**, not by disk:

| Dataset | Contigs | Size | Result |
|---|---:|---:|---|
| `/vol/data/datasets/comebin_tiny` | 100 | 43 MB | ❌ **fails**: `cluster.py` builds an HNSW index and queries `max_edges + 1 = 101` neighbours (`max_edges_list = [100]`, `ef = max_edges*10`) → `RuntimeError: Cannot return the results in a contiguous 2D array. Probably ef or M is too small` for N = 100 ≤ 101; no Leiden result → `ValueError: max() arg is an empty sequence` in `get_final_result.get_bin_quality` (run `tiny_test_n100`, exit 1, 85 s) |
| `/vol/data/datasets/comebin_tiny_101` | **101** | **47 MB** | ✅ **passes**: run `tiny_test_n101`, exit 0, wall 85 s, **1 non-empty bin**; CheckM2 **63.89 % / 9.05 %** (MQ 1), CheckM v1 **46.58 % / 6.35 %** → [`results/tiny_test_n101.csv`](../results/tiny_test_n101.csv) |

**The smallest functional COMEBin dataset on this VM is therefore 101 contigs
(≈ 1.82 Mbp, 47 MB on disk)** — 100 is the first failing size and 101 the first
passing one (both verified end-to-end). It trains with the batch size capped to
the contig count (`run_comebin.sh` clamps `-b` to `sequence_count`), 30 epochs
(issue #10 `-E`), and yields ≥ 1 bin as required.

Optional follow-up fix (not applied — belongs to a fix batch): clamp the
neighbour query to `k = min(max_edges + 1, N)` (and/or shrink `max_edges` for
small inputs) in `cluster.py` so datasets smaller than 101 contigs also work;
until then 101 is the documented floor.

Run with a different dataset: `DATA=/vol/data/datasets/comebin_tiny_101 bash
scripts/run_small_test.sh <fresh_rundir> 8`.

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

### CAMI II human host-associated — issue #18 "Benchmark size" (sample 0 prepped 2026-09-25)

| | |
|---|---|
| Source | **CAMI II Toy Human Microbiome Project** (CAMISIM simulation of HMP body sites), block 2 = gastrointestinal + oral — `https://frl.publisso.de/data/frl:6425518/` |
| Archive | `gastrooral/sample_0.tar.gz` — **9,738,621,091 B**, md5 `60e04c041c38ea168af03fc55dff15d6` ✅ verified (`md5sum -c`) 2026-09-25 01:43 UTC; server md5 from `md5sums.tsv` in the same directory |
| Downloaded to | `/vol/data/datasets/cami_II_human/gastrooral_sample_0.tar.gz` (~97 MB/s, 100 s) |
| Members | `2017.12.04_18.45.54_sample_0/{bam,contigs,reads}` — `bam/` = **139 per-OTU BAMs** (same "per-genome BAMs do not merge" problem as marine), `contigs/` = `anonymous_gsa.fasta.gz` (**68,417 contigs**) + `gsa_mapping.tsv.gz` + `gsa_mapping_new.tsv.gz`, `reads/` = `anonymous_reads.fq` (**10.6 GB, uncompressed**, interleaved PE `@S0R0/1`+`@S0R0/2`) + `reads_mapping.tsv.gz` (293 MB, read → **genome**) + `subsample_0.{sam,bam,fq}` |
| Extracted (contigs + reads only, `bam/` skipped) | `/vol/data/datasets/cami_II_human/extract/2017.12.04_18.45.54_sample_0/` |
| Input decision (issue #18: "1/6 the size of the big one") | 29,434 demo contigs / 6 ≈ 4,900 → **top 4,900 GSA contigs by length** (166.0 Mbp; the 4,900th is 4,733 bp; ≥5,000 bp would give 4,462) + **all** reads mapped `bwa mem -p -t 32` → `human_sample0_input/{contigs.fa,bamfiles/human.bam}` |
| Prep script | [`scripts/prep_cami2_human.sh`](../scripts/prep_cami2_human.sh) (refuses to overwrite an existing build; writes `logs/input_meta.txt` with md5s) |
| Ground truth | ⚠️ `binning_gs.tsv` is **not** inside `sample_0.tar.gz` (only the gsa name maps) → bin quality is scored with CheckM2 + CheckM v1 like every other run; the gold-standard binning lives in `setup.tar.gz` (1.8 GB) / the CAMI goldstandard bundle → **TODO** if a recall/ARI evaluation is wanted |
| Expected wall time | ≈ 1/6 of the 6.9 h demo run → **≈ 1 h** for 200 epochs (verified by the run once launched) |

## 3. CAMI III challenge data (planned)

**Verified 2026-09-25 from <https://cami-challenge.org/datasets/> (HTTP):**

| | |
|---|---|
| Datasets released | **Human gut only so far** — no CAMI III marine/plant yet: (a) *Longitudinal Human Gut* (9 individuals × 4 time points), (b) *Toy Longitudinal Human Gut* (10 individuals × 2 time points = **20 samples**). Both short **and** long reads. |
| Download lists | `https://cami-challenge.org/static/CAMI3_toy_dataset_download.list` (short, 86 URLs) · `…_long_download.list` (long) → `wget -i` |
| Object store | `https://s3.bi.denbi.de/swift/v1/cami3__human-gut-toy/{short,long}/` — per-sample `sample_N_{bam,contigs,gsa,reads}.tar.gz` (N = 0..19) + pooled `gsa_pooled.fasta.gz`, `coverages.tar.gz`, `taxonomic_profiles.tar.gz`, `source_genomes.tar.gz`, `sample_subject_mapping.tsv` |
| Sample IDs | `cami3_toy_human_gut_short_read_sample_[0..19]`; `…_pooled_assembly` = gold-standard pooled assembly |
| Sizes measured (HTTP HEAD, 2026-09-25) | sample 0 short: `bam` **3.6 GB** · `contigs` **277 MB** · `reads` **4.6 GB** · `gsa` **131 MB** → ≈ **8.6 GB/sample**; `gsa_pooled.fasta.gz` 1.2 GB; `coverages.tar.gz` 105 KB → one sample ≈ 8.6 GB, two ≈ 17 GB (budget ≤ 50 GB ✅) |
| Spec | Illumina HiSeq 2×150 bp, 100 Gbp total (short); ONT ~4 kb mean, 100 Gbp (long) |
| Taxonomy | NCBI taxdump `taxdmp_2025-08-01.zip` |
| Ground truth | gold-standard pooled assembly + per-sample `gsa`/`gsa_mapping` (details to confirm on download) |
| Key difference vs CAMI II | **per-sample BAM archives are published** → if the BAM references match the published sample contigs, no `bwa mem` remap is needed (must verify first — CAMI II's BAMs were per-genome and unusable) |
| Status | **to download after the CAMI II marine run**; sample-0 sizes verified; DOI "TBA" (cite the datasets page meanwhile) |
