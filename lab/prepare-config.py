#!/usr/bin/env python3
"""Create a QEMU-only machine config; generated secrets stay under _out/."""

from pathlib import Path
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: prepare-config.py <controlplane.yaml> <extension-config.yaml> <output.yaml>")

base = Path(sys.argv[1]).read_text()
rules = Path(sys.argv[2]).read_text()
for old, new in (
    ("disk: /dev/sda #", "disk: /dev/vda #"),
    ("certSANs: []", "certSANs: [127.0.0.1]"),
):
    if base.count(old) != 1:
        raise SystemExit(f"expected exactly one {old!r} in generated config")
    base = base.replace(old, new)

Path(sys.argv[3]).write_text(base.rstrip() + "\n---\n" + rules)
