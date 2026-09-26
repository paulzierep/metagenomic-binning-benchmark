#!/usr/bin/env bash
# zenodo_update.sh [--dry-run] — issue #8:
# "store all benchmark data in the same record, update continously when new
# benchmark data is made" (owner 2026-09-25; scope clarified 09:04: only data
# that is newly generated and not publicly available otherwise).
#
# Packages the newly generated benchmark data
#   - results/            aggregate CSVs + figures (all runs)
#   - runs/               per-run mirrors (run_meta.txt, comebin_run.log,
#                         per_bin_results.csv, per_bins.png)
#   - runs/<r>/comebin_res/comebin_res_bins/   bin FASTAs produced by COMEBin
#   - runs/<r>/eval/...   CheckM2 quality_report.tsv + CheckM v1
#                         bin_stats_ext.tsv/checkm.log (key eval reports)
#   - docs/ README.md PROGRESS.md status/agent-activity.log
# into a deterministic release tarball with a SHA-256 manifest, then publishes
# it as a NEW VERSION of the existing record (concept DOI
# 10.5281/zenodo.22935024; v1 = 10.5281/zenodo.22935025). Versions accumulate
# under the same concept record, so the concept DOI always resolves to the
# newest package.
#
# Behaviour:
#   - skips silently (exit 0) when content is unchanged since the last upload
#   - skips silently (exit 0) when no token file is present, so it is safe
#     inside run_eval.sh's best-effort auto-reporting chain
#   - exits 1 on packaging/API errors (callers in run_eval.sh treat as warning)
#   --dry-run: package + manifest + change detection, no network calls
#
# Env: ZENODO_TOKEN_FILE (default: ~/.zenodo_token), ZENODO_RECORD (default
# 22935025), ZENODO_UPDATE=0 disables the script entirely.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
RUNS_ROOT=${RUNS_ROOT:-/vol/data/benchmark/runs}
RELEASES=${RELEASES:-/vol/data/benchmark/releases}
META=${META:-/vol/data/benchmark/meta}
TOKEN_FILE=${ZENODO_TOKEN_FILE:-$HOME/.zenodo_token}
RECORD=${ZENODO_RECORD:-22935025}
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

log() { echo "[zenodo_update] $*"; }
skip() { log "skip: $*"; exit 0; }
die() { log "ERROR: $*" >&2; exit 1; }

[ "${ZENODO_UPDATE:-1}" = "0" ] && skip "ZENODO_UPDATE=0"
command -v curl >/dev/null || skip "curl not available"
if [ "$DRY" -eq 0 ]; then
  [ -r "$TOKEN_FILE" ] || skip "no token file at $TOKEN_FILE"
  TOK=$(tr -d '\n' < "$TOKEN_FILE")
fi
command -v python3 >/dev/null || die "python3 not available"
mkdir -p "$RELEASES" "$META"

# --- Stage the package -------------------------------------------------------
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
STAGE=$(mktemp -d "$RELEASES/stage.XXXXXX")
WORK=""
cleanup() { rm -rf "$STAGE" ${WORK:+"$WORK"}; }
trap cleanup EXIT

log "staging benchmark data -> $STAGE"
cp -a "$REPO/results" "$REPO/runs" "$REPO/docs" "$STAGE/"
cp -a "$REPO/README.md" "$REPO/PROGRESS.md" "$STAGE/"
mkdir -p "$STAGE/status"
[ -f "$REPO/status/agent-activity.log" ] && \
  cp -a "$REPO/status/agent-activity.log" "$STAGE/status/"

RUNS_INCLUDED=()
for rd in "$RUNS_ROOT"/*/; do
  [ -d "$rd" ] || continue
  name=$(basename "$rd")
  bins="$rd/comebin_out/comebin_res/comebin_res_bins"
  n_bins=0
  if [ -d "$bins" ]; then
    # Bin FASTAs are the primary run output; dereference possible symlinks.
    dst="$STAGE/runs/$name/comebin_res/comebin_res_bins"
    mkdir -p "$dst"
    while IFS= read -r f; do
      cp -L "$f" "$dst/" && n_bins=$((n_bins + 1))
    done < <(find -L "$bins" -maxdepth 1 -type f -size +0c 2>/dev/null)
  fi
  for rel in eval/checkm2/quality_report.tsv \
             eval/checkm/out/storage/bin_stats_ext.tsv \
             eval/checkm/out/checkm.log; do
    if [ -f "$rd$rel" ]; then
      mkdir -p "$STAGE/runs/$name/$(dirname "$rel")"
      cp -a "$rd$rel" "$STAGE/runs/$name/$rel"
    fi
  done
  # Only evaluated/completed runs with real content belong in the release.
  if [ -f "$STAGE/runs/$name/run_meta.txt" ] && \
     { [ "$n_bins" -gt 0 ] || [ -f "$STAGE/runs/$name/per_bin_results.csv" ]; }; then
    RUNS_INCLUDED+=("$name ($n_bins bins)")
  else
    rm -rf "$STAGE/runs/$name"
  fi
done
[ "${#RUNS_INCLUDED[@]}" -gt 0 ] || die "no evaluated runs found under $RUNS_ROOT"
log "runs in package: ${RUNS_INCLUDED[*]}"

# --- Manifest + change detection ---------------------------------------------
# make_release_manifest.py refuses an output inside the dataset dir, so hash
# outside, then copy the manifest into the stage so it ships in the tarball.
MANIFEST="$RELEASES/manifest.$STAMP.json"
python3 "$REPO/scripts/make_release_manifest.py" "$STAGE" "$MANIFEST" \
  --omit-local-path \
  --metadata source_repo="https://github.com/paulzierep/metagenomic-binning-benchmark" \
  --metadata source_commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)" \
  --metadata kind="benchmark-results" \
  --metadata runs="$(IFS=,; echo "${RUNS_INCLUDED[*]}")" \
  --metadata created_utc="$STAMP" >/dev/null
log "manifest: $(python3 -c "import json,sys;d=json.load(open('$MANIFEST'));print(len(d['files']),'files,',sum(f['bytes'] for f in d['files']),'bytes')")"
cp "$MANIFEST" "$STAGE/manifest.json"

CONTENT_SHA=$(python3 - "$MANIFEST" <<'PY'
import hashlib, json, sys
m = json.load(open(sys.argv[1]))
h = hashlib.sha256()
for f in m["files"]:
    # Activity/status logs are appended to constantly and are provenance, not
    # benchmark data — they must not trigger a new version on their own.
    if f["path"].startswith("status/"):
        continue
    h.update(f"{f['sha256']}  {f['path']}\n".encode())
print(h.hexdigest())
PY
)
LAST="$META/zenodo_last_content.sha256"
if [ -f "$LAST" ] && [ "$(cat "$LAST")" = "$CONTENT_SHA" ]; then
  skip "content unchanged since last upload (sha256 $CONTENT_SHA)"
fi

# --- Build the deterministic tarball -----------------------------------------
build_tar() {
  tar --sort=name --owner=0 --group=0 --numeric-owner \
      --mtime='2020-01-01 00:00:00Z' -cf - -C "$STAGE" . | gzip -n > "$1"
}

if [ "$DRY" -eq 1 ]; then
  OUT="$RELEASES/comebin_benchmark_release_dryrun_$(date -u +%Y%m%d).tar.gz"
  build_tar "$OUT"
  log "package: $OUT ($(stat -c%s "$OUT") bytes, md5 $(md5sum "$OUT" | cut -d' ' -f1))"
  log "dry-run: stopping before any network call"
  exit 0
fi

# --- Zenodo: reuse an open draft or start a new version -----------------------
WORK=$(mktemp -d "$RELEASES/api.XXXXXX")
req() { # METHOD URL [curl args...] -> $CODE (body in $WORK/resp.json)
  local method=$1 url=$2; shift 2
  CODE=$(curl -sS -o "$WORK/resp.json" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $TOK" "$@" "$url")
}

req GET "https://zenodo.org/api/deposit/depositions"
[ "$CODE" = "200" ] || die "listing depositions failed (HTTP $CODE): $(head -c 300 "$WORK/resp.json")"
DRAFT_ID=$(python3 - "$WORK/resp.json" <<'PY'
import json, sys
for d in json.load(open(sys.argv[1])):
    if str(d.get("conceptrecid")) == "22935024" and d.get("state") == "unsubmitted":
        print(d["id"]); break
PY
)
if [ -z "$DRAFT_ID" ]; then
  req GET "https://zenodo.org/api/records/$RECORD/versions"
  [ "$CODE" = "200" ] || die "versions lookup failed (HTTP $CODE)"
  LATEST_ID=$(python3 - "$WORK/resp.json" <<'PY'
import json, sys
hits = json.load(open(sys.argv[1]))["hits"]["hits"]
print(max(int(h["id"]) for h in hits))
PY
)
  req POST "https://zenodo.org/api/deposit/depositions/$LATEST_ID/actions/newversion"
  [ "$CODE" = "201" ] || die "creating new version failed (HTTP $CODE): $(head -c 300 "$WORK/resp.json")"
  DRAFT_ID=$(python3 -c "import json;print(json.load(open('$WORK/resp.json'))['id'])")
  log "created new version draft $DRAFT_ID (from record $LATEST_ID)"
else
  log "reusing open draft $DRAFT_ID"
fi
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

# Version number = published versions + 1 (v1 exists -> this upload is v2).
req GET "https://zenodo.org/api/records/$RECORD/versions"
[ "$CODE" = "200" ] || die "versions lookup failed (HTTP $CODE)"
VERSION=$(python3 - "$WORK/resp.json" <<'PY'
import json, sys
print(len(json.load(open(sys.argv[1]))["hits"]["hits"]) + 1)
PY
)
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

OUT="$RELEASES/comebin_benchmark_release_v${VERSION}_$(date -u +%Y%m%d).tar.gz"
build_tar "$OUT"
OUT_MD5=$(md5sum "$OUT" | cut -d' ' -f1)
log "package: $OUT ($(stat -c%s "$OUT") bytes, md5 $OUT_MD5)"
log "uploading as Zenodo version $VERSION"

# --- Upload file via the record's file bucket ---------------------------------
req GET "https://zenodo.org/api/deposit/depositions/$DRAFT_ID"
[ "$CODE" = "200" ] || die "reading draft failed (HTTP $CODE)"
BUCKET=$(python3 -c "import json;print(json.load(open('$WORK/resp.json'))['links']['bucket'])")
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

FNAME=$(basename "$OUT")
req PUT "$BUCKET/$FNAME" -H "Content-Type: application/octet-stream" \
  --data-binary "@$OUT"
[ "$CODE" = "201" ] || die "file upload failed (HTTP $CODE): $(head -c 300 "$WORK/resp.json")"
UP_MD5=$(python3 -c "import json;print(json.load(open('$WORK/resp.json'))['checksum'].replace('md5:',''))")
[ "$UP_MD5" = "$OUT_MD5" ] || die "uploaded md5 $UP_MD5 != local $OUT_MD5"
log "uploaded $FNAME (md5 verified $OUT_MD5)"
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

# --- Metadata for the new version ---------------------------------------------
req GET "https://zenodo.org/api/deposit/depositions/$DRAFT_ID"
[ "$CODE" = "200" ] || die "reading draft metadata failed (HTTP $CODE)"
python3 - "$WORK/resp.json" "$WORK/meta.json" "$VERSION" "${RUNS_INCLUDED[*]}" <<'PY'
import json, sys, datetime
draft, out, version, runs = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3], sys.argv[4]
md = draft.get("metadata", {})
md["version"] = f"{version}.0"
md["publication_date"] = datetime.date.today().isoformat()
md["title"] = "COMEBin metagenomic binning benchmark — datasets and run results"
md["description"] = (
    "Benchmark of metagenomic genome binners (starting with COMEBin v1.1.0) with a "
    "repeatable harness: per-run parameters, datasets, wall time, and bin quality "
    "scored with CheckM2 and CheckM (v1). Repository: "
    "https://github.com/paulzierep/metagenomic-binning-benchmark (setup, datasets, "
    "evaluation and run docs under docs/; resume state in PROGRESS.md).\n\n"
    "This record accumulates ALL newly generated benchmark data that is not "
    "publicly available otherwise, as continuous versions under the concept DOI "
    "10.5281/zenodo.22935024 (each new evaluated run publishes a new version).\n\n"
    f"Version {version}.0 (this version) contains the benchmark results of every "
    f"evaluated run: {runs}. Each run contributes its bin FASTAs "
    "(runs/<run>/comebin_res/comebin_res_bins/), per-bin and aggregate CheckM2 + "
    "CheckM v1 metrics (results/<run>.csv, runs/<run>/per_bin_results.csv), the "
    "evaluation reports (runs/<run>/eval/), run parameters and logs "
    "(run_meta.txt, comebin_run.log), all comparison figures "
    "(results/figures/, incl. the combined completeness bar plot), plus dataset, "
    "environment, fix, evaluation and preservation documentation (docs/). "
    "manifest.json inside the archive lists every file with size and SHA-256.\n\n"
    "Version 1.0 additionally contains the small functional-test dataset "
    "(comebin_small_release_v1.tar.gz, 300 contigs + overlapping reads).\n\n"
    "How to run: clone the repository, follow docs/02/06 to build the "
    "environment, run a dataset with scripts/run_comebin_fix.sh and evaluate "
    "with scripts/run_eval.sh; docs/01-datasets.md and docs/11-run-results.md "
    "describe each dataset and run."
)
json.dump({"metadata": md}, open(out, "w"), indent=1)
PY
req PUT "https://zenodo.org/api/deposit/depositions/$DRAFT_ID" \
  -H "Content-Type: application/json" --data-binary "@$WORK/meta.json"
[ "$CODE" = "200" ] || die "metadata update failed (HTTP $CODE): $(head -c 300 "$WORK/resp.json")"
log "metadata updated (version $VERSION.0, title/description refreshed)"
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

# --- Publish + verify ---------------------------------------------------------
# Zenodo's publish action may answer 202 (Accepted) and finish asynchronously;
# poll the deposition until its state is `done` before verifying.
req POST "https://zenodo.org/api/deposit/depositions/$DRAFT_ID/actions/publish"
case "$CODE" in
  200|201|202) ;;
  *) die "publish failed (HTTP $CODE): $(head -c 400 "$WORK/resp.json")" ;;
esac
NEW_ID=$(python3 -c "import json;print(json.load(open('$WORK/resp.json')).get('id') or '$DRAFT_ID')")
NEW_DOI=$(python3 -c "
import json;d=json.load(open('$WORK/resp.json'));print(d.get('doi') or d.get('metadata',{}).get('doi') or '')")
for _ in 1 2 3 4 5 6 7 8 9 10; do
  req GET "https://zenodo.org/api/deposit/depositions/$DRAFT_ID"
  [ "$CODE" = "200" ] || die "polling draft state failed (HTTP $CODE)"
  STATE=$(python3 -c "import json;print(json.load(open('$WORK/resp.json')).get('state',''))")
  [ "$STATE" = "done" ] && break
  sleep 3
done
[ "${STATE:-}" = "done" ] || die "deposition did not reach state=done (state=${STATE:-unknown})"
log "published record $NEW_ID (doi $NEW_DOI)"
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

req GET "https://zenodo.org/api/records/$NEW_ID"
[ "$CODE" = "200" ] || die "post-publish record lookup failed (HTTP $CODE)"
python3 - "$WORK/resp.json" "$FNAME" "$(stat -c%s "$OUT")" "$OUT_MD5" <<'PY'
import json, sys
rec, fname, size, md5 = json.load(open(sys.argv[1])), sys.argv[2], int(sys.argv[3]), sys.argv[4]
files = rec.get("files", {}).get("entries", {}) or {
    f.get("key") or f.get("filename"): f for f in rec.get("files", [])}
entry = files.get(fname)
if entry is None:
    sys.exit(f"uploaded file {fname} missing from published record")
est = entry.get("checksum", "")
if est.replace("md5:", "") != md5:
    sys.exit(f"published md5 {est} != local {md5}")
if int(entry.get("size", entry.get("bytes", -1))) != size:
    sys.exit("published size mismatch")
print(f"verified published file {fname}: {size} bytes md5 {md5}")
PY
if [ -n "$NEW_DOI" ]; then
  DOI_HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -L "https://doi.org/$NEW_DOI")
  log "doi.org/$NEW_DOI -> HTTP $DOI_HTTP"
else
  DOI_HTTP=""
fi
rm -rf "$WORK"; WORK=$(mktemp -d "$RELEASES/api.XXXXXX")

# --- Receipt + change marker --------------------------------------------------
RECEIPT="$META/zenodo_benchmark_release_v${VERSION}.json"
python3 - "$RECEIPT" "$VERSION" "$NEW_ID" "$NEW_DOI" "$FNAME" \
  "$(stat -c%s "$OUT")" "$OUT_MD5" "$CONTENT_SHA" "$(IFS=,; echo "${RUNS_INCLUDED[*]}")" "$DOI_HTTP" <<'PY'
import json, sys, datetime
keys = ["receipt_path", "version", "record_id", "doi", "filename", "bytes",
        "md5", "content_sha256", "runs", "doi_resolver_http"]
d = dict(zip(keys, sys.argv[1:11]))
d["published_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
d["concept_doi"] = "10.5281/zenodo.22935024"
d["state"] = "published_verified"
json.dump(d, open(sys.argv[1], "w"), indent=2, sort_keys=True)
print("receipt:", sys.argv[1])
PY
echo "$CONTENT_SHA" > "$LAST"
log "done — version $VERSION published under concept DOI 10.5281/zenodo.22935024"
rm -rf "$WORK"
