#!/usr/bin/env bash
set -euo pipefail

override_file=test/fixtures/with-dep/overrides.nix
trap 'rm -f "$override_file"' EXIT

nix eval --impure --file ./test
nix eval --impure --file ./test/lib.nix
cp test/fixtures/with-dep/overrides.nix.in "$override_file"
nix eval --impure --file ./test/local-overrides.nix
FLAKE_COMPATISH_DISABLE_OVERRIDES=1 nix eval --impure --file ./test/disabled-overrides.nix
nix eval --no-write-lock-file ./test#pureLocalOverride
