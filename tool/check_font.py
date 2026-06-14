#!/usr/bin/env python3
"""Check whether a TrueType/OpenType font contains key Material icon glyphs."""

from __future__ import annotations

import sys
from pathlib import Path


def u32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "big")


def u16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "big")


def read_codepoints(path: Path) -> set[int]:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError("Font file is too small to contain a table directory.")

    num_tables = u16(data, 4)
    tables: dict[str, int] = {}
    for i in range(num_tables):
        base = 12 + i * 16
        tag = data[base : base + 4].decode("ascii", "replace")
        tables[tag] = u32(data, base + 8)

    if "cmap" not in tables:
        raise ValueError("Font does not contain a cmap table.")

    cmap_offset = tables["cmap"]
    num_subtables = u16(data, cmap_offset + 2)
    codepoints: set[int] = set()

    for i in range(num_subtables):
        base = cmap_offset + 4 + i * 8
        subtable = cmap_offset + u32(data, base + 4)
        fmt = u16(data, subtable)

        if fmt == 4:
            seg_count = u16(data, subtable + 6) // 2
            ends = [u16(data, subtable + 14 + 2 * j) for j in range(seg_count)]
            starts = [
                u16(data, subtable + 16 + 2 * seg_count + 2 * j)
                for j in range(seg_count)
            ]
            for start, end in zip(starts, ends):
                codepoints.update(range(start, end + 1))
        elif fmt == 12:
            group_count = u32(data, subtable + 12)
            for j in range(group_count):
                group = subtable + 16 + j * 12
                start = u32(data, group)
                end = u32(data, group + 4)
                codepoints.update(range(start, end + 1))

    return codepoints


CHECKS = {
    "engineering": 0xE3F6,
    "receipt_long": 0xEF6E,
    "inventory_2": 0xE9B9,
    "dashboard": 0xE871,
    "shopping_cart": 0xE8CC,
    "person": 0xE7FD,
    "settings": 0xE8B8,
    "build": 0xE869,
    "category": 0xE574,
    "content_cut": 0xE14E,
    "analytics": 0xEA98,
    "storefront": 0xF830,
    "list_alt": 0xE0EE,
    "groups": 0xF233,
    "tune": 0xE429,
}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: tool/check_font.py PATH_TO_FONT", file=sys.stderr)
        return 2

    path = Path(argv[1])
    if not path.is_file():
        print(f"Font file not found: {path}", file=sys.stderr)
        return 2

    codepoints = read_codepoints(path)
    missing = []

    print(f"Total codepoints: {len(codepoints)}")
    for name, codepoint in CHECKS.items():
        status = "OK" if codepoint in codepoints else "MISSING"
        if status == "MISSING":
            missing.append(name)
        print(f"  {name:20s} U+{codepoint:05X}  {status}")

    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
