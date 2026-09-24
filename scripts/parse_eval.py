#!/usr/bin/env python3
"""Append CheckM2 and CheckM v1 means to a run's metadata.

CheckM2 emits a normal TSV table. CheckM v1 1.2.x emits a bin-id column followed
by a Python-dict representation in ``bin_stats_ext.tsv``; accept both formats so
an apparently successful CheckM process cannot silently lose its metrics.
"""
import ast
import os
import sys

run = sys.argv[1]
meta = os.path.join(run, "run_meta.txt")


def scores(path):
    if not os.path.exists(path):
        return [], []
    completeness, contamination = [], []
    with open(path, encoding="utf-8") as handle:
        first = handle.readline().rstrip("\n")
        first_parts = first.split("\t", 1)
        header_parts = first.split("\t")
        is_dict_row = len(first_parts) == 2 and first_parts[1].lstrip().startswith("{")
        if not is_dict_row and "Completeness" in header_parts and "Contamination" in header_parts:
            ci = header_parts.index("Completeness")
            ti = header_parts.index("Contamination")
            lines = [first, *handle]
            for line in lines:
                parts = line.rstrip("\n").split("\t")
                try:
                    completeness.append(float(parts[ci]))
                    contamination.append(float(parts[ti]))
                except (ValueError, IndexError):
                    continue
            return completeness, contamination
        # CheckM v1: '<bin-id>\t<dict literal>\n' with no header row.
        lines = [first, *handle] if is_dict_row else handle
        for line in lines:
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) != 2:
                continue
            try:
                record = ast.literal_eval(parts[1])
                completeness.append(float(record["Completeness"]))
                contamination.append(float(record["Contamination"]))
            except (KeyError, TypeError, ValueError, SyntaxError):
                continue
    return completeness, contamination


rows = []
checkm2 = scores(os.path.join(run, "eval", "checkm2", "quality_report.tsv"))
if checkm2[0]:
    c, t = checkm2
    rows.append(
        f"checkm2_bins: {len(c)} checkm2_compl_mean: {sum(c)/len(c):.2f} "
        f"checkm2_cont_mean: {sum(t)/len(t):.2f}"
    )

checkm1 = scores(os.path.join(run, "eval", "checkm", "out", "storage", "bin_stats_ext.tsv"))
if checkm1[0]:
    c, t = checkm1
    rows.append(
        f"checkm_bins: {len(c)} checkm_compl_mean: {sum(c)/len(c):.2f} "
        f"checkm_cont_mean: {sum(t)/len(t):.2f}"
    )

# Replace prior derived metric lines so rerunning evaluation is idempotent.
metric_prefixes = ("checkm2_bins:", "checkm_bins:")
try:
    with open(meta, encoding="utf-8") as handle:
        existing = handle.readlines()
except FileNotFoundError:
    existing = []
kept = [line for line in existing if not line.startswith(metric_prefixes)]
with open(meta, "w", encoding="utf-8") as handle:
    handle.writelines(kept)
    for row in rows:
        handle.write(row + "\n")
print("\n".join(rows) if rows else "no eval results found")
