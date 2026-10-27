#!/usr/bin/env bash
# Impure evaluation copies nothing to the store that the result does not
# need. Each case evaluates against an empty chroot store and then requires
# that store to be empty. The fixtures have only local inputs, and no
# forced value interpolates a path, so any store path is a copy that
# flake-compatish made.
set -euo pipefail

work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT

no_copy() {
  local name=$1 expr=$2
  shift 2
  local root="$work/$name"
  mkdir -p "$root"
  nix eval --store "local?root=$root" --impure --json "$@" --expr "
    let
      fc = import ./.;
      fixtures = ./test/fixtures;
      parity = ./test/parity;
    in
    $expr" >/dev/null
  local copied
  copied=$(find "$root/nix/store" -mindepth 1 -maxdepth 1 ! -name .links 2>/dev/null || true)
  if [ -n "$copied" ]; then
    echo "FAILED: no_copy $name copied to the store:" >&2
    echo "$copied" >&2
    exit 1
  fi
}

top='with (fc { source = parity + "/top"; }).outputs; [ value nestedValue selfSourceInfo midSourceInfo (toString selfOutPath) (toString leafOutPath) (toString midOutPath) ]'
no_copy attrset-form "$top"
no_copy path-form 'with (fc (parity + "/top")).outputs; [ value nestedValue (toString leafOutPath) ]'
no_copy string-source 'with (fc { source = toString (parity + "/top"); }).outputs; [ value nestedValue ]'
no_copy outpath-source 'with (fc { source = { outPath = parity + "/top"; }; }).outputs; [ value nestedValue ]'
no_copy path-override '
  with (fc { source = fixtures + "/with-dep"; overrides.simple = fixtures + "/simple-local"; }).outputs;
  [ simpleValue (toString simplePath) (toString selfPath) ]'
no_copy string-override '
  with (fc { source = fixtures + "/with-dep"; overrides.simple = toString (fixtures + "/simple-local"); }).outputs;
  [ simpleValue (toString simplePath) ]'
no_copy missing-override '
  with (fc { source = fixtures + "/with-dep"; overrides.simple = "/nonexistent-flake-compatish"; }).outputs;
  [ simpleValue ]'
no_copy system-override '
  with (fc { source = fixtures + "/deep"; systemOverrides = fixtures + "/system-overrides.nix"; }).outputs;
  [ nestedSimpleValue ]'
no_copy compatish-override '
  with ((fc (fixtures + "/with-dep")).compatish.override { overrides.simple = fixtures + "/simple-local"; }).outputs;
  [ simpleValue ]'
FLAKE_COMPATISH_DISABLE_OVERRIDES=1 no_copy overrides-disabled "$top"
echo '"All no-copy tests passed!"'
