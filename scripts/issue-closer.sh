#!/usr/bin/env bash
# issue-closer.sh — deterministically close GitHub issues that have been marked
# as addressed. Pure shell + `gh`; ZERO LLM tokens.
#
# Contract (for agents, the supervisor, and humans):
#   When an issue's work is VERIFIED complete, write ONE line — a short closing
#   reason — to a marker file:
#       /vol/data/benchmark/meta/.issues_done/<number>
#   The next meta-watchdog tick runs this script, which:
#     - verifies the issue is still open on GitHub,
#     - closes it with the recorded reason as the closing comment,
#     - re-verifies it is closed (no trusting the close call's exit code alone),
#     - records it in meta/issues_closed.tsv + meta/.issues_closed/<number>,
#     - advances meta/.issues_seen/<number> so meta-watchdog stops escalating it.
#   Never close an issue by any other automation path.
#
# Safety: max closes per run (default 5), no force, idempotent markers.
# Concurrency: per-script flock + shared repo lock only for the git publish.
set -u
export HOME=/home/ubuntu
export PATH=/home/ubuntu/.opencode/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin
export GIT_TERMINAL_PROMPT=0

BENCH=/vol/data/benchmark
REPO=/vol/data/repos/metagenomic-binning-benchmark
META="$BENCH/meta"
DONE="$META/.issues_done"
CLOSED="$META/.issues_closed"
SEEN="$META/.issues_seen"
LOG="$BENCH/logs/issue-closer.log"
REPO_LOCK=${BENCH_REPO_LOCK:-/tmp/bench-repo.lock}
LOCK=${ISSUE_CLOSER_LOCK:-/tmp/issue-closer.lock}
REPO_URL=paulzierep/metagenomic-binning-benchmark
MAX_PER_RUN=${ISSUE_CLOSE_MAX:-5}

mkdir -p "$DONE" "$CLOSED" "$SEEN" "$BENCH/logs"
log() { echo "$(date -Is) [issue-closer] $*" >>"$LOG"; }

exec 9>"$LOCK"
flock -n 9 || exit 0

closed=0
failed=""
[ -f "$META/issues_closed.tsv" ] || printf 'closed_at\tnumber\ttitle\treason\n' > "$META/issues_closed.tsv"

for marker in "$DONE"/*; do
  [ -f "$marker" ] || continue
  num=$(basename "$marker")
  case "$num" in *[!0-9]*|'') log "skipping non-numeric marker '$num'"; rm -f "$marker"; continue ;; esac

  # NOTE: .issues_closed/<num> is only a record of a PAST close. The user can
  # reopen an issue after we close it (e.g. a follow-up request on the same
  # issue), and a new marker must then be able to close it again. Never use the
  # local record to skip the live GitHub state check below — only GitHub's
  # current state decides whether this marker archives or closes.

  if [ "$closed" -ge "$MAX_PER_RUN" ]; then
    log "hit MAX_PER_RUN=$MAX_PER_RUN; leaving remaining markers for next tick"
    break
  fi

  reason=$(head -c 400 "$marker" | tr '\n' ' ')
  state=$(timeout 30s gh issue view "$num" -R "$REPO_URL" --json state --jq .state 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)
  case "$state" in
    closed)
      log "#$num already closed on GitHub; archiving marker"
      printf '%s\n' "$reason" > "$CLOSED/$num"
      rm -f "$marker"
      continue
      ;;
    open) : ;;
    *)
      log "#$num state lookup failed ($state); keeping marker for retry"
      continue
      ;;
  esac

  title=$(timeout 30s gh issue view "$num" -R "$REPO_URL" --json title --jq .title 2>/dev/null | head -c 120)
  if timeout 45s gh issue close "$num" -R "$REPO_URL" \
       --comment "Closed by automation — addressed: $reason" 2>/dev/null; then
    newstate=$(timeout 30s gh issue view "$num" -R "$REPO_URL" --json state --jq .state 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo unknown)
    if [ "$newstate" = "closed" ]; then
      closed=$((closed + 1))
      printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$num" "$title" "$reason" \
        >> "$META/issues_closed.tsv"
      printf '%s\n' "$reason" > "$CLOSED/$num"
      printf '%s\n' "$(date +%s)" > "$SEEN/$num"     # stop meta-watchdog re-escalating it
      printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "closed #$num ($title)" >> "$META/close-log.txt"
      log "closed #$num ($title): $reason"
      rm -f "$marker"
    else
      failed="$failed #$num(verify=$newstate)"
      log "close #$num call OK but verify showed state=$newstate; marker kept for retry"
    fi
  else
    failed="$failed #$num"
    log "FAILED to close #$num"
  fi
done

# ---- publish recorded closures to GitHub (only when something happened) ------ #
if [ "$closed" -gt 0 ] || [ -n "$failed" ]; then
  mkdir -p "$REPO/status/meta"
  cp "$META/issues_closed.tsv" "$REPO/status/meta/issues_closed.tsv" 2>/dev/null || true
  cp "$META/close-log.txt" "$REPO/status/meta/issue-close-log.txt" 2>/dev/null || true
  (
    exec 8>"$REPO_LOCK"
    flock -w 20 8 || exit 0
    cd "$REPO" || exit 0
    git add status/meta/issues_closed.tsv status/meta/issue-close-log.txt
    if ! git diff --cached --quiet -- status/meta; then
      git commit -q --only -m "meta: issue-closer closed $closed, failed:$failed — $(date -u +%H:%MZ)" -- status/meta || exit 0
    fi
    timeout 60s git push -q || exit 0
  )
fi

if [ -n "$failed" ]; then
  log "RESULT closed=$closed failed:$failed"
  exit 1
fi
log "RESULT closed=$closed (no failures)"
exit 0