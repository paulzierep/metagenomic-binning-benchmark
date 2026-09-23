#!/usr/bin/env python3
"""Create a deterministic, checksum-backed manifest for a dataset release.

The manifest is deliberately independent of Zenodo: it is a reviewable staging
artifact that can be attached to a deposition after an owner has approved the
release and supplied credentials.  Large benchmark inputs are never copied into
this repository by this tool.

Usage:
  python3 scripts/make_release_manifest.py DATASET_DIR OUTPUT.json \\
      --metadata source_commit=<sha> --metadata dataset=demo-small

The output is JSON with sorted relative paths, byte sizes, and streaming SHA-256
hashes.  Existing output is refused unless --force is supplied.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


def parse_metadata(values: Iterable[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"metadata must be KEY=VALUE, got {value!r}")
        key, item = value.split("=", 1)
        key = key.strip()
        if not key:
            raise ValueError("metadata key must not be empty")
        result[key] = item
    return dict(sorted(result.items()))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_excluded(relative: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(relative, pattern) for pattern in patterns)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset_dir", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--metadata",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="provenance field to include (repeatable)",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="GLOB",
        help="relative-path glob to omit (repeatable)",
    )
    parser.add_argument("--force", action="store_true", help="replace an existing manifest")
    args = parser.parse_args()

    dataset = args.dataset_dir.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if not dataset.is_dir():
        parser.error(f"dataset directory does not exist: {dataset}")
    try:
        output.relative_to(dataset)
    except ValueError:
        pass
    else:
        parser.error("manifest output must be outside the dataset directory")
    if output.exists() and not args.force:
        parser.error(f"output exists (use --force to replace it): {output}")

    try:
        metadata = parse_metadata(args.metadata)
    except ValueError as exc:
        parser.error(str(exc))

    files: list[dict[str, object]] = []
    for path in sorted(dataset.rglob("*"), key=lambda item: item.as_posix()):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(dataset).as_posix()
        if is_excluded(relative, args.exclude):
            continue
        size = path.stat().st_size
        files.append({"path": relative, "bytes": size, "sha256": sha256(path)})

    manifest = {
        "schema_version": 1,
        "dataset_name": dataset.name,
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "dataset_path": str(dataset),
        "metadata": metadata,
        "file_count": len(files),
        "total_bytes": sum(int(item["bytes"]) for item in files),
        "files": files,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp.{os.getpid()}")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    temporary.replace(output)
    print(f"wrote {output} ({len(files)} files, {manifest['total_bytes']} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
