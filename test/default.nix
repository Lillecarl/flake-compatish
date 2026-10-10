# Test suite for flake-compatish
# Run with: nix eval --impure --file ./test/test.nix
let
  flake-compatish = import ../.;

  # Helper to check if path is in nix store
  isStorePath = path: builtins.substring 0 11 (builtins.toString path) == "/nix/store/";

  # Helper to run assertion with descriptive error
  assert' =
    name: condition: message:
    if condition then true else builtins.throw "FAILED: ${name} - ${message}";

  # Get absolute path for fixtures
  fixturesPath = builtins.toString ./fixtures;

  #
  # Test cases
  #

  # Test 1: Default behavior - source should be copied to store
  test_default_copies_to_store =
    let
      result = flake-compatish { source = ./fixtures/simple; };
    in
    assert' "default_copies_to_store" (isStorePath result.outputs.selfPath)
      "Expected selfPath to be in /nix/store, got: ${result.outputs.selfPath}";

  # Test 2: overrides.self - source should NOT be copied to store
  test_override_self_no_store =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "override_self_no_store" (
      !(isStorePath result.outputs.selfPath)
    ) "Expected selfPath to NOT be in /nix/store, got: ${result.outputs.selfPath}";

  # Test 3: Outputs are correctly resolved
  test_outputs_resolved =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "outputs_resolved" (
      result.outputs.testValue == "hello from simple"
    ) "Expected testValue to be 'hello from simple', got: ${result.outputs.testValue}";

  # Test 4: Input override works
  test_input_override =
    let
      overridePath = "${fixturesPath}/simple";
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = ./fixtures/simple;
        };
      };
    in
    assert' "input_override" (
      result.outputs.simplePath == overridePath
    ) "Expected simplePath to be '${overridePath}', got: ${result.outputs.simplePath}";

  # Test 5: Dependency values are accessible
  test_dependency_values =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = ./fixtures/simple;
        };
      };
    in
    assert' "dependency_values" (
      result.outputs.simpleValue == "hello from simple"
    ) "Expected simpleValue to be 'hello from simple', got: ${result.outputs.simpleValue}";

  # Test 6: Lockless flake works with override
  test_lockless_with_override =
    let
      result = flake-compatish {
        source = ./fixtures/lockless;
        overrides.self = ./fixtures/lockless;
      };
    in
    assert' "lockless_with_override" (
      result.outputs.testValue == "hello from lockless"
    ) "Expected testValue to be 'hello from lockless', got: ${result.outputs.testValue}";

  # Test 7: Lockless flake works with default (store copy)
  test_lockless_default =
    let
      result = flake-compatish { source = ./fixtures/lockless; };
    in
    assert' "lockless_default" (isStorePath result.outputs.selfPath)
      "Expected selfPath to be in /nix/store for lockless default, got: ${result.outputs.selfPath}";

  # Test 8: inputs attrset contains self
  test_inputs_has_self =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "inputs_has_self" (result.inputs ? self) "Expected inputs to contain 'self' attribute";

  # Test 9: _type is "flake"
  test_flake_type =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "flake_type" (
      result.outputs._type == "flake"
    ) "Expected _type to be 'flake', got: ${result.outputs._type}";

  # Test 10: String override (flake ref) is fetched to store
  test_string_override_fetches =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          # Use path: flake ref as string - should be fetched to store
          simple = "path:${fixturesPath}/simple";
        };
      };
    in
    assert' "string_override_fetches" (isStorePath result.outputs.simplePath)
      "Expected simplePath to be in /nix/store when using string flake ref, got: ${result.outputs.simplePath}";

  # Test 11: String override still resolves values correctly
  test_string_override_values =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = "path:${fixturesPath}/simple";
        };
      };
    in
    assert' "string_override_values" (result.outputs.simpleValue == "hello from simple")
      "Expected simpleValue to be 'hello from simple' with string override, got: ${result.outputs.simpleValue}";

  # Test 12: Nonexistent path override for self falls back to fetchTree (with warning)
  test_nonexistent_self_override_fallback =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides = {
          # This path doesn't exist - should warn and fall back to fetchTree
          self = /nonexistent/path/that/does/not/exist;
        };
      };
    in
    assert' "nonexistent_self_override_fallback" (isStorePath result.outputs.selfPath)
      "Expected selfPath to be in /nix/store after fallback, got: ${result.outputs.selfPath}";

  # Test 13: A consumer without overrides.nix proceeds normally.
  test_no_local_override_file =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "no_local_override_file" (
      result.outputs.testValue == "hello from simple"
    ) "Expected a consumer without overrides.nix to evaluate normally";

  # Test 14: Unknown keys must not be forced at all.
  test_unknown_override_is_lazy =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides = {
          self = ./fixtures/simple;
          not-an-input = throw "unknown override was forced";
        };
      };
    in
    assert' "unknown_override_is_lazy" (
      result.outputs.testValue == "hello from simple"
    ) "Expected unknown override keys to be ignored without forcing their values";

  # Test 15: The optional local override file can be configured explicitly.
  test_configured_overrides_file =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = "path:${fixturesPath}/simple";
        };
        overridesFile = ./fixtures/with-dep/custom-overrides.nix;
      };
    in
    assert' "configured_overrides_file" (
      result.outputs.simplePath == "${fixturesPath}/simple"
    ) "Expected the configured local override file to take precedence";

  # Test 16: Override warnings can be disabled without changing resolution.
  test_warn_overrides_disabled =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
        warnOverrides = false;
      };
    in
    assert' "warn_overrides_disabled" (
      result.outputs.testValue == "hello from simple"
    ) "Expected overrides to resolve when warnings are disabled";

  # Test 17: One configured package set replaces self.legacyPackages for both
  # the root flake and its resolved input flakes.
  test_shared_legacy_packages =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = ./fixtures/simple;
          nixpkgs = ./fixtures/fake-nixpkgs;
        };
        nixpkgsArgs = system: {
          inherit system;
          marker = "master-configured";
        };
      };
    in
    assert' "shared_legacy_packages" (
      result.outputs.selfLegacyMarker == "master-configured"
      && result.outputs.simpleLegacyMarker == "master-configured"
    ) "Expected the shared package set to replace self.legacyPackages throughout the graph";

  # Test 18: Without the option, every flake retains its own package set.
  test_default_legacy_packages =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = ./fixtures/simple;
        };
      };
    in
    assert' "default_legacy_packages" (
      result.outputs.selfLegacyMarker == "with-dep-local"
      && result.outputs.simpleLegacyMarker == "simple-local"
    ) "Expected each flake to retain its own legacyPackages without an injected package set";

  # Test 19: An override cannot reach an input two levels down. `deep` does
  # not declare `simple`, so the name is not one of its root inputs and the
  # override is ignored. This is the case `reroot` exists for.
  test_override_misses_nested =
    let
      result = flake-compatish {
        source = ./fixtures/deep;
        overrides = {
          self = ./fixtures/deep;
          simple = ./fixtures/simple;
        };
      };
    in
    assert' "override_misses_nested" (
      result.outputs.nestedSimplePath == "${fixturesPath}/deep/../with-dep/../simple"
    )
      "Expected the nested simple to come from the lockfile, got: ${result.outputs.nestedSimplePath}";

  # Test 20: reroot reaches it, because the key is the input name that
  # with-dep uses and not the node the lockfile named.
  test_reroot_reaches_nested =
    let
      simple = (flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      }).outputs;
      result = flake-compatish {
        source = ./fixtures/deep;
        overrides.self = ./fixtures/deep;
        reroot = { inherit simple; };
      };
    in
    assert' "reroot_reaches_nested" (
      result.outputs.nestedSimplePath == fixturesPath + "/simple"
    ) "Expected the nested simple to be the local one, got: ${result.outputs.nestedSimplePath}";

  # Test 21: reroot replaces the flake and not only its source, so a value
  # the rerooted flake computes is the one that arrives.
  test_reroot_replaces_outputs =
    let
      simple = (flake-compatish { source = ./fixtures/simple; }).outputs // {
        testValue = "hello from a rerooted simple";
      };
      result = flake-compatish {
        source = ./fixtures/deep;
        reroot = { inherit simple; };
      };
    in
    assert' "reroot_replaces_outputs" (
      result.outputs.nestedSimpleValue == "hello from a rerooted simple"
    ) "Expected the rerooted outputs, got: ${result.outputs.nestedSimpleValue}";

  # Collect all tests
  allTests = [
    test_override_misses_nested
    test_reroot_reaches_nested
    test_reroot_replaces_outputs
    test_default_copies_to_store
    test_override_self_no_store
    test_outputs_resolved
    test_input_override
    test_dependency_values
    test_lockless_with_override
    test_lockless_default
    test_inputs_has_self
    test_flake_type
    test_string_override_fetches
    test_string_override_values
    test_nonexistent_self_override_fallback
    test_no_local_override_file
    test_unknown_override_is_lazy
    test_configured_overrides_file
    test_warn_overrides_disabled
    test_shared_legacy_packages
    test_default_legacy_packages
  ];

  # Run all tests - if any fail, the whole eval fails with a descriptive error
  runTests = builtins.all (x: x) allTests;

in
if runTests then
  "All ${toString (builtins.length allTests)} tests passed!"
else
  builtins.throw "Some tests failed"
