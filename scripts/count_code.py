#!/usr/bin/env python3
"""count_code.py — report MoonBit line counts for moon-content-disposition.

Counts non-blank, non-comment lines per category:

  core       — package-root *.mbt files that are not test files
  tests      — package-root *_test.mbt files
  cli        — cmd/**/*.mbt
  examples   — examples/**/*.mbt

Line counting: a line is "code" if, after stripping leading whitespace, it is
not empty and does not start with `//` or `///`. Multi-line `/* */` comments
are not used in this codebase, so a single-pass strip is accurate.

Usage: python3 scripts/count_code.py [root]
"""

import os
import sys

COMMENT_START = ("//", "/*", "*")


def is_blank_or_comment(line: str) -> bool:
    s = line.strip()
    if not s:
        return True
    if s.startswith("//"):
        return True
    if s.startswith("/*"):
        return True
    if s.startswith("*"):
        return True
    return False


def count_mbt_files(paths):
    total_code = 0
    total_lines = 0
    total_files = 0
    for p in sorted(paths):
        with open(p, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
        code = sum(1 for ln in lines if not is_blank_or_comment(ln))
        total_lines += len(lines)
        total_code += code
        total_files += 1
    return total_files, total_lines, total_code


def walk_mbt(root_dir, prefix):
    paths = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in ("_build", "target")]
        for fn in filenames:
            if fn.endswith(".mbt"):
                paths.append(os.path.join(dirpath, fn))
    return [p for p in paths if p.startswith(prefix)]


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.path.abspath(root)

    core_files = []
    test_files = []
    for fn in sorted(os.listdir(root)):
        if not fn.endswith(".mbt"):
            continue
        p = os.path.join(root, fn)
        if fn.endswith("_test.mbt"):
            test_files.append(p)
        else:
            core_files.append(p)

    cli_files = walk_mbt(os.path.join(root, "cmd"), root)
    example_files = walk_mbt(os.path.join(root, "examples"), root)

    categories = [
        ("core", core_files),
        ("tests", test_files),
        ("cli", cli_files),
        ("examples", example_files),
    ]

    print(f"{'category':<10} {'files':>6} {'lines':>8} {'code':>8}")
    print("-" * 38)
    grand_files = grand_lines = grand_code = 0
    per = {}
    for name, files in categories:
        nf, nl, nc = count_mbt_files(files)
        per[name] = (nf, nl, nc)
        grand_files += nf
        grand_lines += nl
        grand_code += nc
        print(f"{name:<10} {nf:>6} {nl:>8} {nc:>8}")
    print("-" * 38)
    print(f"{'total':<10} {grand_files:>6} {grand_lines:>8} {grand_code:>8}")
    print("")
    library = per["core"][2] + per["cli"][2] + per["examples"][2]
    print(f"library_total (core+cli+examples) = {library}")
    print("note: 'code' excludes blank lines and //-comment lines.")


if __name__ == "__main__":
    main()
