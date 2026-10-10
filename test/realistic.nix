# A repository shaped like a real one, overridden the ways a user would.
# test/integration.sh runs this with HOME set to test/fixtures, so `~` names
# the fixtures, and with the NIX_PATH entry pointing at
# fixtures/realistic-system-overrides.nix.
let
  flake-compatish = import ../.;

  assert' =
    name: condition: message:
    if condition then true else builtins.throw "FAILED: ${name} - ${message}";

  home = builtins.getEnv "HOME";
  fixturesPath = builtins.toString ./fixtures;

  # Both copies of nixpkgs, and the tool, from one NIX_PATH file that uses `~`.
  test_nix_path_file_reaches_both_copies =
    let
      result = flake-compatish ./fixtures/realistic;
    in
    assert' "nix_path_file_reaches_both_copies"
      (result.outputs.rootMarker == "default" && result.outputs.toolMarker == "default")
      "Expected github:NixOS/nixpkgs to replace nixpkgs and nixpkgs_2, got: ${result.outputs.rootMarker}, ${result.outputs.toolMarker}";

  # A key with a branch replaces only that copy.
  test_branch_key_splits_copies =
    let
      result = flake-compatish {
        source = ./fixtures/realistic;
        systemOverrides = {
          "github:NixOS/nixpkgs" = ./fixtures/fake-nixpkgs;
          "github:NixOS/nixpkgs/nixos-24.05" = ./fixtures/simple;
          "github:Example/Tool" = ./fixtures/realistic-tool;
        };
      };
    in
    assert' "branch_key_splits_copies"
      (result.outputs.rootMarker == "default" && result.outputs.toolMarker == "simple-local")
      "Expected the 24.05 key for the tool's copy only, got: ${result.outputs.rootMarker}, ${result.outputs.toolMarker}";

  test_tilde_in_local_file =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overridesFile = ./fixtures/tilde-overrides.nix;
      };
    in
    assert' "tilde_in_local_file" (
      result.outputs.simpleValue == "hello from lockless"
      && result.outputs.simplePath == "${home}/lockless"
    ) "Expected ~/lockless to resolve under HOME, got: ${result.outputs.simplePath}";

  # The form a committed file should use: pure evaluation reads `~` as a
  # parse error, and this as a missing path, which falls back to the lockfile.
  test_home_from_environment =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides.simple = /. + builtins.getEnv "HOME" + "/lockless";
      };
    in
    assert' "home_from_environment" (
      result.outputs.simpleValue == "hello from lockless"
    ) "Expected the HOME-based path to apply, got: ${result.outputs.simpleValue}";

  allTests = [
    test_nix_path_file_reaches_both_copies
    test_branch_key_splits_copies
    test_tilde_in_local_file
    test_home_from_environment
  ];
in
if home != fixturesPath then
  builtins.throw "run with HOME=${fixturesPath}, got HOME=${home}"
else if builtins.all (x: x) allTests then
  "All ${toString (builtins.length allTests)} realistic tests passed!"
else
  builtins.throw "Some tests failed"
