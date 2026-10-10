"""Turn nixdoc's Markdown into MyST that Sphinx accepts.

nixdoc writes the nixpkgs manual dialect. MyST rejects two parts of it: a
`{#anchor}` after a heading, and `:::{.example}` blocks, which it reads as
a directive named `.example`. Headings also move down one level, under the
page title.

Reads stdin, writes stdout. Fails if either construct survives, so a change
in nixdoc's output breaks the build instead of the page.
"""

from __future__ import annotations

import re
import sys

ANCHOR = re.compile(r"\s*\{#[^}]*\}\s*$")
EXAMPLE_FENCE = re.compile(r"^:::(\{\.example\})?\s*$")


def convert(lines: list[str]) -> tuple[list[str], list[str]]:
    """Return the converted lines, and the lines outside code it could not convert."""
    out = ["# API reference", ""]
    left: list[str] = []
    in_code = False
    for line in lines:
        if line.startswith("```"):
            in_code = not in_code
        elif not in_code:
            if EXAMPLE_FENCE.match(line):
                continue
            if line.startswith("#"):
                line = "#" + ANCHOR.sub("", line)
            if ANCHOR.search(line) or line.startswith(":::"):
                left.append(line)
        out.append(line)
    return out, left


def main() -> None:
    out, left = convert(sys.stdin.read().splitlines())
    if left:
        sys.exit("nixdoc_to_myst: unconverted lines:\n" + "\n".join(left))
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
