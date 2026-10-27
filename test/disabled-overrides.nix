# This test is run by test/integration.sh with
# FLAKE_COMPATISH_DISABLE_OVERRIDES set.  Neither a supplied override nor a
# local override file may be applied while it is set.  The root stays in
# place all the same: impure evaluation copies no path source.
#
# The with-dep fixture's lockfile pins its inputs by relative path, which
# `fetchTree` cannot resolve on its own, so only `selfPath` is forced there.
let
  flake-compatish = import ../.;

  suppliedIgnored =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/lockless;
      };
    in
    if result.outputs.selfPath != ./fixtures/simple then
      throw "expected the supplied self override to be ignored, got ${toString result.outputs.selfPath}"
    else if result.outputs.testValue != "hello from simple" then
      throw "expected the lockfile source to evaluate, got ${result.outputs.testValue}"
    else
      true;

  localFileIgnored =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overridesFile = ./fixtures/with-dep/self-overrides.nix;
      };
    in
    if result.outputs.selfPath != ./fixtures/with-dep then
      throw "expected the local override file to be ignored, got ${toString result.outputs.selfPath}"
    else
      true;

  systemIgnored =
    let
      result = flake-compatish {
        source = ./fixtures/deep;
        systemOverrides = ./fixtures/system-overrides.nix;
      };
    in
    if result.outputs.nestedSimpleValue != "hello from simple" then
      throw "expected the system-wide overrides to be ignored, got ${result.outputs.nestedSimpleValue}"
    else
      true;

in
if suppliedIgnored && localFileIgnored && systemIgnored then
  "overrides disabled"
else
  throw "unreachable"
