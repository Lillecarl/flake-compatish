# Tests for system-wide overrides. Run with:
#   nix eval --impure --file ./test/system-overrides.nix \
#     -I flake-compatish-overrides=./test/fixtures/system-overrides.nix
let
  flake-compatish = import ../.;

  assert' =
    name: condition: message:
    if condition then true else builtins.throw "FAILED: ${name} - ${message}";

  fixturesPath = builtins.toString ./fixtures;

  # Matches with-dep's `simple`, which no name override from deep reaches.
  nestedSimple = {
    "path:../simple" = ./fixtures/lockless;
  };

  test_owner_and_repo_ignore_case =
    let
      result = flake-compatish {
        source = ./fixtures/by-ref;
        systemOverrides = {
          "github:example/leaf" = ./fixtures/simple;
          "leaf" = ./fixtures/simple;
        };
      };
    in
    assert' "owner_and_repo_ignore_case" (
      result.outputs.leafValue == "hello from simple"
    ) "Expected github:example/leaf to match Example/Leaf, got: ${result.outputs.leafValue}";

  # `registered` is written as the registry name `leaf`. Its locked
  # reference is github:Example/Leaf with no ref, so only the key without a
  # ref matches it, and the key with one wins for `leaf`.
  test_more_specific_key_wins =
    let
      result = flake-compatish {
        source = ./fixtures/by-ref;
        systemOverrides = {
          "github:Example/Leaf" = ./fixtures/lockless;
          "github:Example/Leaf/main" = ./fixtures/simple;
        };
      };
    in
    assert' "more_specific_key_wins"
      (
        result.outputs.leafValue == "hello from simple"
        && result.outputs.registeredValue == "hello from lockless"
      )
      "Expected the ref key for leaf and the locked match for registered, got: ${result.outputs.leafValue}, ${result.outputs.registeredValue}";

  test_reaches_nested =
    let
      result = flake-compatish {
        source = ./fixtures/deep;
        systemOverrides = nestedSimple;
      };
    in
    assert' "reaches_nested" (
      result.outputs.nestedSimpleValue == "hello from lockless"
    ) "Expected the system-wide override two levels down, got: ${result.outputs.nestedSimpleValue}";

  test_beats_supplied =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides.simple = ./fixtures/simple;
        systemOverrides = nestedSimple;
      };
    in
    assert' "beats_supplied" (
      result.outputs.simpleValue == "hello from lockless"
    ) "Expected the system-wide override to beat overrides, got: ${result.outputs.simpleValue}";

  test_loses_to_local_file =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overridesFile = ./fixtures/with-dep/custom-overrides.nix;
        systemOverrides = nestedSimple;
      };
    in
    assert' "loses_to_local_file" (
      result.outputs.simplePath == "${fixturesPath}/simple"
    ) "Expected the local file to beat the system-wide override, got: ${result.outputs.simplePath}";

  test_unusable_value_passes_on =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides.simple = ./fixtures/simple;
        systemOverrides."path:../simple" = /nonexistent/flake-compatish;
      };
    in
    assert' "unusable_value_passes_on" (result.outputs.simplePath == "${fixturesPath}/simple")
      "Expected a missing system-wide path to fall through to overrides, got: ${result.outputs.simplePath}";

  test_function_form =
    let
      result = flake-compatish {
        source = ./fixtures/deep;
        systemOverrides =
          { nodeName, original, ... }:
          if nodeName == "simple" && original.type == "path" then ./fixtures/lockless else null;
      };
    in
    assert' "function_form" (
      result.outputs.nestedSimpleValue == "hello from lockless"
    ) "Expected the function to override simple, got: ${result.outputs.nestedSimpleValue}";

  # The rest read the NIX_PATH entry the run sets.
  test_nix_path_entry =
    let
      result = flake-compatish { source = ./fixtures/deep; };
    in
    assert' "nix_path_entry" (
      result.outputs.nestedSimpleValue == "hello from lockless"
    ) "Expected the NIX_PATH file to apply, got: ${result.outputs.nestedSimpleValue}";

  test_opt_out =
    let
      result = flake-compatish {
        source = ./fixtures/deep;
        systemOverrides = false;
      };
    in
    assert' "opt_out" (result.outputs.nestedSimpleValue == "hello from simple")
      "Expected systemOverrides = false to ignore the NIX_PATH file, got: ${result.outputs.nestedSimpleValue}";

  allTests = [
    test_owner_and_repo_ignore_case
    test_more_specific_key_wins
    test_reaches_nested
    test_beats_supplied
    test_loses_to_local_file
    test_unusable_value_passes_on
    test_function_form
    test_nix_path_entry
    test_opt_out
  ];
in
if builtins.any (entry: entry.prefix == "flake-compatish-overrides") builtins.nixPath then
  if builtins.all (x: x) allTests then
    "All ${toString (builtins.length allTests)} system override tests passed!"
  else
    builtins.throw "Some tests failed"
else
  builtins.throw "run with -I flake-compatish-overrides=./test/fixtures/system-overrides.nix"
