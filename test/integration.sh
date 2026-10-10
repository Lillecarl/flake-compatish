#!/usr/bin/env bash
set -euo pipefail

override_file=test/fixtures/with-dep/overrides.nix
log=$(mktemp)
trap 'rm -f "$override_file" "$log"' EXIT

# Run a command that must fail, and require `pattern` in what it prints.
expect_error() {
  local pattern=$1
  shift
  if "$@" >"$log" 2>&1; then
    echo "expected an error: $*" >&2
    exit 1
  fi
  if ! grep -qF -- "$pattern" "$log"; then
    echo "expected '$pattern' from: $*" >&2
    cat "$log" >&2
    exit 1
  fi
}

# Only nixpkgs, for doc/default.nix. A machine's own
# flake-compatish-overrides entry would otherwise apply to every test. The
# variable wins over nix.conf's nix-path.
NIX_PATH="nixpkgs=$(nix eval --impure --raw --expr 'toString <nixpkgs>')"
export NIX_PATH
system_overrides="flake-compatish-overrides=$PWD/test/fixtures/system-overrides.nix"

nix eval --impure --file ./test
nix eval --impure --file ./test/lib.nix
nix eval --impure --file ./test/system-overrides.nix -I "$system_overrides"
nix eval --impure --file ./test/parity.nix

# HOME names the fixtures, so `~` does too. The XDG variables keep Nix's
# own cache, state and config where they were. `real_home` is read first:
# a prefix assignment's expansion already sees the new HOME.
real_home="$HOME"
HOME="$PWD/test/fixtures" \
  XDG_CACHE_HOME="${XDG_CACHE_HOME:-$real_home/.cache}" \
  XDG_STATE_HOME="${XDG_STATE_HOME:-$real_home/.local/state}" \
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$real_home/.config}" \
  XDG_DATA_HOME="${XDG_DATA_HOME:-$real_home/.local/share}" \
  nix eval --impure --file ./test/realistic.nix \
  -I "flake-compatish-overrides=$PWD/test/fixtures/realistic-system-overrides.nix"

stale() {
  nix eval --impure --expr "(import ./. ./test/fixtures/stale/$1).outputs.${2:-testValue}"
}
expect_error 'flake.lock does not have: `another`, `extra`. Run `nix flake lock`.' stale missing
expect_error 'and there is no flake.lock: `simple`.' stale lockless-inputs
expect_error 'node `simple` of' nix eval --impure --expr \
  '(import ./. { source = ./test/fixtures/with-dep; overrides.simple = ./test/fixtures/stale/missing; }).outputs.simpleValue'
# A changed url warns, and the locked reference still applies.
stale changed-url simpleValue >"$log" 2>&1
grep -qF 'changes the url of `simple`' "$log"
grep -qxF '"hello from simple"' "$log"
# A removed input warns, and is not passed to `outputs`.
stale removed >"$log" 2>&1
grep -qF 'does not declare: `simple`. flake-compatish ignores them.' "$log"
grep -qxF '"hello from stale/removed"' "$log"

# An error in a nested input names the input path.
nested() {
  nix eval --impure --expr "(import ./. { source = ./test/fixtures/deep; systemOverrides.\"path:../simple\" = $1; }).outputs.nestedSimpleValue"
}
expect_error 'while evaluating the flake input `with-dep → simple`' nested ./test/fixtures/broken
expect_error 'while fetching the flake input `with-dep → simple`' nested '"path:/nonexistent-flake-compatish"'

nix build --no-link --file ./doc site
cp test/fixtures/with-dep/overrides.nix.in "$override_file"
nix eval --impure --file ./test/local-overrides.nix
# Impure with no HOME or USER: the local file must still apply.
env -i PATH="$PATH" nix eval --impure --file ./test/local-overrides.nix
FLAKE_COMPATISH_DISABLE_OVERRIDES=1 nix eval --impure --file ./test/disabled-overrides.nix -I "$system_overrides"
nix eval --no-write-lock-file ./test#pureLocalOverride
nix eval --no-write-lock-file ./test#pureSystemOverride
nix eval --no-write-lock-file ./test#pureTildeFileNotRead
