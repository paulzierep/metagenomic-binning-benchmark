#!/usr/bin/env bash
# run_sweep_medium.sh — drive the issue-#25 optimization sweep on the medium
# dataset, ONE cell at a time, fully detached, resumable.
#
# Design (matches docs/13-optimization-sweep-medium.md):
#   * 24 cells: 1-factor-at-a-time around the reference defaults on the v11
#     pin 95f5ea8 (worktree /vol/data/repos/COMEBin-v11-sweep), plus pins:
#       - cell 2  -> unmodified upstream master @ 904f649
#                    (/vol/data/repos/COMEBin-master904; CPU-only, no -d/-s:
#                     unseeded by design = matches original baseline semantics)
#       - cell 3  -> v11 @ 41606c8 (issue #28 fix) = no-regression check
#   * seed 42 for every seeded cell EXCEPT cell 24 = seed 7 reproducibility
#     check (Sweep spec col 10 holds the per-cell seed; "ref" -> default 42).
#   * THREADS=8 default (medium is small; leave cores for eval + agent)
#   * each cell: run via bin/run_comebin_fix.sh (self-registers .active_run,
#     watchdog owns handoff) then bin/run_eval.sh (CheckM2 + CheckM + auto
#     results CSV + per-bin plots).
#   * resume: a run_meta.txt with exit_code 0 but no results csv gets EVAL'd
#     ("orphaned"), then treated as done; a dir with a non-zero exit is left
#     for manual triage (never auto-retried, never overwritten).
#   * never overlaps the registered benchmark run: WAITS up to WAIT_MAX_S for
#     .active_run to clear when a foreign run is registered at start.
#
# Usage:
#   THREADS=8 bash scripts/run_sweep_medium.sh [--only NAME] [--from N]
# Logs:  /vol/data/benchmark/status/sweep_medium.log

set -euo pipefail

BENCH=/vol/data/benchmark
BIN="$BENCH/bin"
ACTIVE="$BENCH/.active_run"
LOG="$BENCH/status/sweep_medium.log"
THREADS=${THREADS:-8}
SEED=${SEED:-42}
WAIT_MAX_S=${WAIT_MAX_S:-14400}   # 4 h: enough to outlast any foreign run
DATA=/vol/data/datasets/comebin_medium
CONTIGS="$DATA/contigs.fa"
BAMDIR="$DATA/bamfiles"
V11="$BENCH/../repos/COMEBin-v11-sweep"   # 95f5ea8 pin (reference base)
V11FIX="$BENCH/../repos/COMEBin-v11"       # 41606c8 (issue #28 fix)
MASTER="$BENCH/../repos/COMEBin-master904" # 904f649 (unmodified master)
RESULTS=/vol/data/repos/metagenomic-binning-benchmark/results
REPO_RUNS=/vol/data/repos/metagenomic-binning-benchmark/runs

[ -f "$CONTIGS" ] || { echo "FATAL: no contigs $CONTIGS" | tee -a "$LOG"; exit 1; }
[ -d "$BAMDIR" ]  || { echo "FATAL: no bamdir $BAMDIR" | tee -a "$LOG"; exit 1; }

mkdir -p "$BENCH/status"

# name|source|temp|emb|emb_cov|batch|max_edges|leiden_workers|hmm_evalue|n_views|seed
CELL_SPECS=(
  "sweep_001_ref|$V11|ref|ref|ref|ref|ref|ref|ref|6|42"
  "sweep_002_master|$MASTER|ref|ref|ref|ref|ref|ref|ref|6|ref"
  "sweep_003_issue28fix|$V11FIX|ref|ref|ref|ref|ref|ref|ref|6|42"
  "sweep_004_temp005|$V11|0.05|ref|ref|ref|ref|ref|ref|6|42"
  "sweep_005_temp030|$V11|0.30|ref|ref|ref|ref|ref|ref|6|42"
  "sweep_006_temp050|$V11|0.50|ref|ref|ref|ref|ref|ref|6|42"
  "sweep_007_emb1024|$V11|ref|1024|ref|ref|ref|ref|ref|6|42"
  "sweep_008_emb4096|$V11|ref|4096|ref|ref|ref|ref|ref|6|42"
  "sweep_009_embcov1024|$V11|ref|ref|1024|ref|ref|ref|ref|6|42"
  "sweep_010_embcov4096|$V11|ref|ref|4096|ref|ref|ref|ref|6|42"
  "sweep_011_batch512|$V11|ref|ref|ref|512|ref|ref|ref|6|42"
  "sweep_012_batch2048|$V11|ref|ref|ref|2048|ref|ref|ref|6|42"
  "sweep_013_edges80|$V11|ref|ref|ref|ref|80|ref|ref|6|42"
  "sweep_014_edges150|$V11|ref|ref|ref|ref|150|ref|ref|6|42"
  "sweep_015_views4|$V11|ref|ref|ref|ref|ref|ref|ref|4|42"
  "sweep_016_views8|$V11|ref|ref|ref|ref|ref|ref|ref|8|42"
  "sweep_017_w4|$V11|ref|ref|ref|ref|ref|4|ref|6|42"
  "sweep_018_w16|$V11|ref|ref|ref|ref|ref|16|ref|6|42"
  "sweep_019_eval1e3|$V11|ref|ref|ref|ref|ref|ref|1e-3|6|42"
  "sweep_020_eval1e7|$V11|ref|ref|ref|ref|ref|ref|1e-7|6|42"
  "sweep_021_comboA|$V11|0.30|1024|ref|512|ref|ref|ref|6|42"
  "sweep_022_comboB|$V11|0.05|4096|ref|2048|ref|ref|ref|6|42"
  "sweep_023_embcov512_batch512|$V11|ref|ref|512|512|ref|ref|ref|6|42"
  "sweep_024_seed7|$V11|ref|ref|ref|ref|ref|ref|ref|6|7"
)

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG"; }

# ---- singleton guard: exactly one sweep driver may exist ---------------- #
# The sweep drives one COMEBin cell at a time against shared state: the run
# slot (.active_run), /tmp/benchmark-start.lock and one log. A second instance
# does not queue politely - it walks the same cell list concurrently,
# clobbers .active_run, and its cells collide with the first instance's.
# That is how the 13:07 launch ended up with three drivers, and how the live
# cell was orphaned (its parent driver died, the child kept training under
# init) instead of being supervised. Same shape as the agent-watchdog and
# benchmark-watchdog guards: flock for new-vs-new, plus a process scan so an
# instance started BEFORE this guard existed is still honoured, not raced.
SWEEP_LOCK=${SWEEP_LOCK:-/tmp/run_sweep_medium.lock}
exec 9>"$SWEEP_LOCK"
if ! flock -n 9; then
  echo "another sweep driver holds $SWEEP_LOCK" >&2
  exit 0
fi
# Process scan for an instance started BEFORE this guard existed. It is
# advisory and confirmed twice, 2 s apart: the launch chain (nohup/setsid
# wrappers, tool shell) briefly shares our argv, and a single-shot scan once
# aborted a perfectly good launch on such a transient. Any pid in our own
# ancestor chain is ignored; a match that survives the second probe is real.
ANCESTORS=" $$ $PPID"
_probe=$PPID
while [ "${_probe:-0}" -gt 1 ] 2>/dev/null; do
  _probe=$(ps -o ppid= -p "$_probe" 2>/dev/null | tr -d ' ')
  [ -n "${_probe:-}" ] || break
  ANCESTORS="$ANCESTORS $_probe"
done
for _attempt in 1 2; do
  _found=""
  for other in $(pgrep -f 'run_sweep_medium\.sh' 2>/dev/null || true); do
    case " $ANCESTORS " in *" $other "*) continue ;; esac
    _found="$other"
  done
  [ -z "$_found" ] && break
  if [ "$_attempt" = 2 ]; then
    log "ABORT: sweep driver pid=$_found already running; singleton guard, not starting a second ($(ps -o args= -p "$_found" 2>/dev/null | cut -c1-160))"
    exit 0
  fi
  sleep 2
done


only=""; from=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac
done

# ---- safety: never overlap a live registered benchmark run --------------- #
wait_active_clear() {
  local waited=0
  while [ -f "$ACTIVE" ]; do
    local active_pid=""
    read -r active_pid _ < "$ACTIVE" || true
    if [ -z "${active_pid:-}" ] || ! kill -0 "$active_pid" 2>/dev/null; then
      log "note: stale .active_run (pid ${active_pid:-?} dead or empty) left by watchdog; continuing"
      return 0
    fi
    if [ "$waited" -ge "$WAIT_MAX_S" ]; then
      log "ABORT: registered run pid=$active_pid still alive after ${waited}s; refusing overlap"
      exit 1
    fi
    log "wait: foreign run pid=$active_pid active (${waited}s elapsed); sleeping 60"
    sleep 60
    waited=$((waited + 60))
  done
}

wait_active_clear

# ---- per-cell helper: wrap up a cell that already has a finished run ------- #
eval_done_run() {
  local name="$1" RUN="$2"
  if [ ! -d "$RUN/comebin_out/comebin_res/comebin_res_bins" ]; then
    log "NOTE $name: exit 0 but no bins dir; not evaling"
    return 0
  fi
  if "$BIN/run_eval.sh" "$RUN" > "$BENCH/status/$name.eval.out" 2>&1; then
    log "DONE $name (orphaned run EVAL'd OK)"
  else
    log "EVAL_FAIL $name (rc=$?) — will re-eval later"
  fi
}

idx=0
for spec in "${CELL_SPECS[@]}"; do
  idx=$((idx + 1))
  [ "$idx" -ge "$from" ] || continue
  IFS='|' read -r name src temp emb emb_cov batch max_edges lw heval nviews cellseed <<< "$spec"
  if [ -n "$only" ] && [ "$name" != "$only" ]; then continue; fi

  RUN="$BENCH/runs/$name"
  if [ -f "$RUN/run_meta.txt" ]; then
    rc=$(grep -m1 '^exit_code:' "$RUN/run_meta.txt" | awk '{print $2}' || true)
    if [ "${rc:-}" = "0" ]; then
      if [ -f "$RESULTS/$name.csv" ]; then
        log "SKIP $name (already done rc=0 + results csv)"
      else
        log "RESUME $name (rc=0 but no results csv — evaling orphaned run)"
        eval_done_run "$name" "$RUN"
      fi
      continue
    fi
    if [ -n "$rc" ] && [ "$rc" != "0" ]; then
      log "SKIP $name (previous exit $rc — needs manual triage, not auto-retried)"
      continue
    fi
    log "SKIP $name (run dir exists without terminal exit — not overwriting)"
    continue
  fi

  # Build env overrides, dropping "ref".
  declare -a SWEEP_ENV=()
  [ "$temp"     != "ref" ] && SWEEP_ENV+=(TEMP="$temp")
  [ "$emb"      != "ref" ] && SWEEP_ENV+=(EMB="$emb")
  [ "$emb_cov"  != "ref" ] && SWEEP_ENV+=(EMB_COV="$emb_cov")
  [ "$batch"    != "ref" ] && SWEEP_ENV+=(BATCH="$batch")
  [ "$max_edges" != "ref" ] && SWEEP_ENV+=(MAX_EDGES="$max_edges")
  [ "$lw"       != "ref" ] && SWEEP_ENV+=(LEIDEN_WORKERS="$lw")
  [ "$heval"    != "ref" ] && SWEEP_ENV+=(HMM_EVALUE="$heval")
  [ "$nviews"   != "6" ] && SWEEP_ENV+=(N_VIEWS="$nviews")
  SEED_FOR_RUN="$SEED"
  [ "$cellseed" != "ref" ] && SEED_FOR_RUN="$cellseed"

  log "START $name src=$(basename "$src") @ $(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo '?') threads=$THREADS seed=$SEED_FOR_RUN temp=$temp emb=$emb emb_cov=$emb_cov batch=$batch max_edges=$max_edges lw=$lw heval=$heval n_views=$nviews"

  if ! env SRC_COMEBIN="$src" DATA="$DATA" CONTIGS="$CONTIGS" BAMDIR="$BAMDIR" \
      MODE=medium THREADS="$THREADS" SEED="$SEED_FOR_RUN" \
      "${SWEEP_ENV[@]}" \
      "$BIN/run_comebin_fix.sh" "$RUN" >> "$BENCH/status/$name.comebin.out" 2>&1; then
    log "FAIL $name: run_comebin_fix.sh rc=$?"
    continue
  fi

  rc=$(grep -m1 '^exit_code:' "$RUN/run_meta.txt" | awk '{print $2}' || true)
  log "RUN_DONE $name exit=${rc:-?}"

  if [ "${rc:-}" != "0" ] || [ ! -d "$RUN/comebin_out/comebin_res/comebin_res_bins" ]; then
    log "FAIL $name: no successful bins; skipping eval"
    continue
  fi

  # brief grace for run_comebin_fix.sh cleanup of .active_run
  sleep 5
  if ! "$BIN/run_eval.sh" "$RUN" > "$BENCH/status/$name.eval.out" 2>&1; then
    log "EVAL_FAIL $name (rc=$?) — results CSV may be missing; will re-eval later"
    continue
  fi
  log "DONE $name (eval OK, results CSV + per-bin plots generated)"

  # sync per-bin artifacts back into the repo run dir
  mkdir -p "$REPO_RUNS/$name"
  cp "$RUN/run_meta.txt" "$REPO_RUNS/$name/run_meta.txt" 2>/dev/null || true
  if [ -f "$RESULTS/$name.csv" ]; then
    cp "$RESULTS/$name.csv" "$REPO_RUNS/$name/" 2>/dev/null || true
  fi
  if [ -f "$RUN/per_bin_results.csv" ]; then
    cp "$RUN/per_bin_results.csv" "$REPO_RUNS/$name/per_bin_results.csv" 2>/dev/null || true
  fi
done

log "SWEEP COMPLETE ($idx cells processed)"
