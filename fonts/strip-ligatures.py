#!/usr/bin/env python3
"""Neutralize ligature features in the vendored Azeret Mono files.

Azeret ships liga/calt/dlig lookups that turn f+i into a ligature and -> into
an arrow. Per-app switches only reach apps that expose one (Qt/Quickshell
ignores fontconfig's fontfeatures), so the features are emptied in the font
instead. Feature records are kept and pointed at no lookups, which avoids
reindexing anything else in GSUB.

Usage: python3 strip-ligatures.py [font-or-dir ...]   (defaults to azaret/)
Needs fonttools. Re-run after replacing the fonts with fresh upstream copies.
"""

import sys
from pathlib import Path

from fontTools.ttLib import TTFont

STRIP = {"liga", "calt", "dlig", "clig", "rlig"}


def strip(path):
    font = TTFont(path)
    if "GSUB" not in font:
        return False
    hit = False
    for record in font["GSUB"].table.FeatureList.FeatureRecord:
        if record.FeatureTag in STRIP and record.Feature.LookupListIndex:
            record.Feature.LookupListIndex = []
            record.Feature.LookupCount = 0
            hit = True
    if hit:
        font.save(path)
    font.close()
    return hit


def main(args):
    roots = [Path(a) for a in args] or [Path(__file__).parent / "azaret"]
    files = sorted(
        f
        for root in roots
        for f in ([root] if root.is_file() else root.rglob("*"))
        if f.suffix.lower() in (".otf", ".ttf")
    )
    assert files, f"no fonts found in {roots}"
    for f in files:
        print(("stripped " if strip(f) else "no change ") + str(f))


if __name__ == "__main__":
    main(sys.argv[1:])
