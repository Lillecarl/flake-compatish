#!/usr/bin/env bash
set -euo pipefail

override_file=test/fixtures/with-dep/overrides.nix
trap 'rm -f "$override_file"' EXIT

# Only nixpkgs, for doc/default.nix. A machine's own
# flake-compatish-overrides entry would otherwise apply to every test. The
# variable wins over nix.conf's nix-path.
NIX_PATH="nixpkgs=$(nix eval --impure --raw --expr 'toString <nixpkgs>')"
export NIX_PATH
system_overrides="flake-compatish-overrides=$PWD/test/fixtures/system-overrides.nix"

nix eval --impure --file ./test
nix eval --impure --file ./test/lib.nix
nix eval --impure --file ./test/system-overrides.nix -I "$system_overrides"

# HOME names the fixtures, so `~` does too. The XDG variables keep Nix's
# own cache, state and config where they were.
HOME="$PWD/test/fixtures" \
  XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}" \
  XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}" \
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
  XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}" \
  nix eval --impure --file ./test/realistic.nix \
  -I "flake-compatish-overrides=$PWD/test/fixtures/realistic-system-overrides.nix"

nix build --no-link --file ./doc site
cp test/fixtures/with-dep/overrides.nix.in "$override_file"
nix eval --impure --file ./test/local-overrides.nix
FLAKE_COMPATISH_DISABLE_OVERRIDES=1 nix eval --impure --file ./test/disabled-overrides.nix -I "$system_overrides"
nix eval --no-write-lock-file ./test#pureLocalOverride
nix eval --no-write-lock-file ./test#pureSystemOverride
nix eval --no-write-lock-file ./test#pureTildeFileNotRead
