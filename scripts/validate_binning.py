#!/usr/bin/env python3
"""validate_binning.py <file.binning> [...]

Structurally validate one or more files against the CAMI binning output format
v0.9.1 (bioboxes/rfc, data-format/binning.mkd). This is a dependency-free
stand-in for the upstream bioboxes/validator container, which is not publicly
distributable for the genome-binning task.

Checks:
  * UTF-8, no CR, only UNIX newlines
  * header lines start with '@'; TAG:VALUE matches the spec regex; tags unique
  * required @Version and @SampleID present
  * exactly one '@@' column-declaration line, with SEQUENCEID and a BINID/TAXID
  * one row per sequence id, SEQUENCEID unique, declared columns present
  * non-empty bin/taxon ids and a sane id charset

Exit code 0 if all files pass, 1 otherwise.
"""
import re
import sys

HEADER_RE = re.compile(r"^@(_[A-Za-z]*_)?[A-Za-z]+[A-Za-z0-9]*:[A-Za-z0-9,.;_|]*$")
ID_RE = re.compile(r"^[A-Za-z0-9._|,:-]+$")


def validate(path):
    errors = []
    warnings = []

    raw = open(path, "rb").read()
    if b"\r" in raw:
        errors.append("contains CR (\\r); only UNIX newlines are allowed")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        return [f"not valid UTF-8: {e}"], warnings

    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    version = None
    sample = None
    seen_tags = set()
    columns = None
    n_data = 0
    seen_seq = set()
    got_output = False

    for i, line in enumerate(lines, 1):
        if line == "" or line.startswith("#"):
            continue
        if line.startswith("@@"):
            if columns is not None:
                errors.append(f"line {i}: more than one '@@' column line")
            columns = line[2:].split("\t")
            got_output = True
            continue
        if line.startswith("@"):
            if got_output:
                errors.append(f"line {i}: header line after output section started")
            if not HEADER_RE.match(line):
                errors.append(f"line {i}: malformed header {line!r}")
                continue
            tag, _, value = line[1:].partition(":")
            tag = tag.upper()
            if tag in seen_tags:
                errors.append(f"line {i}: duplicate header tag {tag}")
            seen_tags.add(tag)
            if tag == "VERSION":
                version = value
            elif tag == "SAMPLEID":
                sample = value
            continue

        # output/data line
        if columns is None:
            errors.append(f"line {i}: data before '@@' column declaration")
            continue
        fields = line.split("\t")
        if len(fields) != len(columns):
            errors.append(
                f"line {i}: expected {len(columns)} fields, got {len(fields)}"
            )
            continue
        row = dict(zip(columns, fields))
        seq = row.get("SEQUENCEID")
        if not seq:
            errors.append(f"line {i}: empty SEQUENCEID")
            continue
        if seq in seen_seq:
            errors.append(f"line {i}: duplicate SEQUENCEID {seq!r}")
        seen_seq.add(seq)
        if not (row.get("BINID") or row.get("TAXID")):
            errors.append(f"line {i}: neither BINID nor TAXID set")
        for col in ("SEQUENCEID", "BINID", "TAXID"):
            val = row.get(col, "")
            if val and not ID_RE.match(val):
                warnings.append(f"line {i}: unusual {col} value {val!r}")
        n_data += 1

    if not got_output:
        errors.append("missing '@@' column declaration line")
    if not version:
        errors.append("missing required @Version header")
    if not sample:
        errors.append("missing required @SampleID header")
    if columns is not None:
        if "SEQUENCEID" not in columns:
            errors.append("'@@' line lacks SEQUENCEID")
        if "BINID" not in columns and "TAXID" not in columns:
            errors.append("'@@' line lacks BINID and TAXID")

    return errors, warnings


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    rc = 0
    for path in argv[1:]:
        errors, warnings = validate(path)
        status = "OK" if not errors else "FAIL"
        print(f"{status}  {path}")
        for w in warnings:
            print(f"    WARN {w}")
        for e in errors:
            print(f"    ERROR {e}")
        if errors:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
