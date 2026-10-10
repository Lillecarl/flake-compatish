from __future__ import annotations

project = "flake-compatish"
author = "Carl Andersson"

extensions = ["myst_parser"]

myst_enable_extensions = ["deflist"]
# The README links to its own sections by GitHub's slugs.
myst_heading_anchors = 3

exclude_patterns = ["_build"]

html_theme = "furo"
html_title = "flake-compatish"

smartquotes = False
