# 12 — COMEBin `master` divergence, and how to work on COMEBin safely

> Written 2026-09-28 after the `paulzierep/COMEBin` `master` branch was found to be
> **diverged**, which silently blocked every push of COMEBin work.
> **Read this before committing to, branching from, or force-pushing `paulzierep/COMEBin`.**

## 1. What went wrong

`master` split at a common ancestor and the two sides never rejoined:

```
                 987db95  "Improve thread usage in cluster.py"   (merge base)
                 /     \
  local  master  /       \  1b476a4  Clarify PyTorch installation options   <- GitHub
              358ddd8    \ ad6ceb3  Release v1.1.0
              904f649     \ fd7ff06  Update Bioconda CUDA example
              ee2e507      \
              47c1449       \
              586c7f7        \
```

- Local `master` carried **5** bug-fix commits (2026-09-23 → 09-24).
- GitHub `master` carried the **3** upstream **v1.1.0 release** commits.
- Both sides pushed at different times, so a plain push was rejected forever:

```
$ git push origin master
 ! [rejected]  master -> master (non-fast-forward)
```

**Root cause:** the local clone was made on 2026-09-23 13:56 UTC. The v1.1.0 release
was pushed to `master` 4 hours later (18:17 UTC) *from a different clone*. The local
clone never fetched that, so all 5 fix commits were built on the stale `987db95` base
and could never be pushed. Nothing was lost, but no COMEBin work could reach GitHub.

## 2. How it was resolved (2026-09-28)

1. Proved all 5 commits were already on GitHub via `comebin-small-fix`:
   - `586c7f7`, `47c1449`, `ee2e507`, `904f649` are the **same SHAs** on that branch.
   - `358ddd8` is patch-id-identical to `c8f22e4` (also on that branch).
2. Pushed a safety branch at the old tip so the pre-v1.1.0 line is permanently
   recoverable **on GitHub**, not just locally:
   `archive/pre-v11-master-20260928` → `358ddd8`
3. Fast-forwarded local `master` to the v1.1.0 release: `master = 1b476a4`.

`master` now tracks the upstream v1.1.0 release, which is the **benchmark baseline**.
That is intentional: pristine COMEBin is what the "unmodified" baseline run needs.

## 3. Porting table — do NOT re-apply these blindly

The 5 pre-v1.1.0 fixes were written against the v1.0.x layout. v1.1.0 rewrote
26 files (+3251/−2515) and **deleted `COMEBin/data_aug/gen_var.py`**. Check this
table before porting anything:

| Fix | Old location | v1.1.0 status | Action |
|---|---|---|---|
| `586c7f7` seed file `FileNotFoundError` | `cluster.py::gen_seed_idx` | **STILL RELEVANT** — `gen_seed_idx` is gone, but `cluster.py::read_seed_names` (line ~248) still does an unguarded `open(seed_file)`. | Port to the new function. See §5. |
| `47c1449` `KeyError` in `gen_cov.py` | `data_aug/gen_cov.py` | **ALREADY FIXED UPSTREAM** — v1.1.0 rewrote the file; it now uses `context.contig_index.get(contig_name)` with an explicit `if index is None:` branch. | Do not port. |
| `ee2e507` `KeyError` in `gen_var.py` | `data_aug/gen_var.py` | **OBSOLETE** — the file is deleted; variance coverage moved into the rewritten `gen_cov.py`, which has the guard. | Do not port. |
| `904f649` `covIdxArr` `np.empty` → `np.zeros` | `get_augfeature.py` | **ALREADY FIXED UPSTREAM** — `covIdxArr` and `np.int` are both gone (`np.int` was removed in numpy 1.24). | Do not port. |
| `358ddd8` KMeans `n_jobs` + private sklearn imports | `cluster.py` | **ALREADY FIXED UPSTREAM** — v1.1.0 uses only public imports (`sklearn.cluster`, `sklearn.metrics.pairwise`, `sklearn.utils`, `sklearn.utils.extmath`) and `KMeans(..., algorithm="lloyd")` with no `n_jobs`. | Do not port. |

**Rule: re-derive a fix against the v1.1.0 source before porting it.** A patch that
conflicted during the v1.1.0 rewrite is usually a fix for a bug that no longer exists.

## 4. Rules for COMEBin work (please follow)

1. **Never force-push `master`, and never reset `master` backwards.** `master` is the
   v1.1.0 baseline. A `push --force` would delete the release history.
2. **`git fetch origin` before creating any branch.** The entire incident was caused
   by branching from a stale local ref.
3. **Fixes live in a branch, one commit per batch** (project convention, see
   `docs/07-fix-batches.md`). The v1.1.0-based line is `comebin-optimizations-v11`.
4. **Verify the push actually landed** — do not trust a zero exit code:
   ```bash
   git push -q && [ "$(git rev-parse HEAD)" = "$(git ls-remote origin refs/heads/<branch> | awk 'NR==1{print $1}')" ] \
     && echo LANDED || echo "NOT PUSHED"
   ```
5. **Before benchmarking a fix batch**, re-run the baseline on the same commit the
   fix batch is based on, so the comparison is like-for-like.

## 5. Current branch layout

| Branch | Tip | Role |
|---|---|---|
| `master` | `1b476a4` | upstream v1.1.0 release — the **baseline** |
| `comebin-optimizations-v11` | *(active)* | fix batches on top of v1.1.0 |
| `comebin-small-fix` | `c8f22e4` | the pre-v1.1.0 fix batch (5 fixes), already on GitHub |
| `comebin-optimizations` | `03670d6` | pre-v1.1.0 optimization line |
| `archive/pre-v11-master-20260928` | `358ddd8` | safety snapshot of the old diverged `master` |

Local clones are **git worktrees of one repo** (`/vol/data/repos/COMEBin`), not
separate clones — so a `master` reset affects them all. Check with
`git -C /vol/data/repos/COMEBin worktree list` before moving branch tips around.
