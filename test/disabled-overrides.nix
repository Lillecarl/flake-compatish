# This test is run by test/integration.sh with
# FLAKE_COMPATISH_DISABLE_OVERRIDES set.  Neither a supplied override nor a
# local override file may be applied while it is set.
#
# The with-dep fixture's lockfile pins its inputs by relative path, which
# `fetchTree` cannot resolve on its own, so only `selfPath` is forced there.
let
  flake-compatish = import ../.;
  isStorePath = path: builtins.substring 0 11 (builtins.toString path) == "/nix/store/";

  suppliedIgnored =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    if !(isStorePath result.outputs.selfPath) then
      throw "expected the supplied self override to be ignored, got ${result.outputs.selfPath}"
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
    if !(isStorePath result.outputs.selfPath) then
      throw "expected the local override file to be ignored, got ${result.outputs.selfPath}"
    else
      true;

in
if suppliedIgnored && localFileIgnored then "overrides disabled" else throw "unreachable"
