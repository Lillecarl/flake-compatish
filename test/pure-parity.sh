#!/usr/bin/env bash
# Pure evaluation, two flakes: each flake in test/parity is evaluated by the
# flake evaluator, and again by test/pure-parity, a flake with no inputs that
# imports it with flake-compatish. Both are `nix eval` of a flake, so both are
# pure. The fixtures must be committed: the flake evaluator reads the git tree.
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A bare string or path has no revision, hash or time to give, and a path
# value normalizes `..`, which the flake evaluator keeps in its strings.
no_source_info='walk(if type == "object" then del(.lastModified, .lastModifiedDate, .narHash, .rev, .revCount, .shortRev, .dirtyRev, .dirtyShortRev, .submodules, .sourceInfo) else . end)'
no_dotdot='walk(if type == "string" then gsub("/[^/]+/\\.\\."; "") | gsub("/[^/]+/\\.\\."; "") else . end)'

compare() {
  local name=$1 variant=$2 filter=$3
  nix eval --json "./test/parity/$name#all" | jq -S "$filter" >"$work/real"
  nix eval --json "./test/pure-parity#$variant.$name" | jq -S "$filter" >"$work/compat"
  if ! diff -u "$work/real" "$work/compat"; then
    echo "FAILED: pure parity of $name, $variant" >&2
    exit 1
  fi
}

for name in leaf mid top; do
  compare "$name" withSourceInfo .
  compare "$name" fromString "$no_source_info"
  compare "$name" fromPath "$no_source_info | $no_dotdot"
done
echo '"All pure parity comparisons passed!"'
