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

  # Test 1: Impure evaluation reads a path source in place, with no override
  test_default_in_place =
    let
      result = flake-compatish { source = ./fixtures/simple; };
    in
    assert' "default_in_place" (result.outputs.selfPath == ./fixtures/simple)
      "Expected selfPath to be the source itself, got: ${toString result.outputs.selfPath}";

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
    ) "Expected selfPath to NOT be in /nix/store, got: ${toString result.outputs.selfPath}";

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

  # Test 4: Input override works. simple-local differs from the lockfile's
  # simple by value, so the value proves which one arrived.
  test_input_override =
    let
      overridePath = "${fixturesPath}/simple-local";
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = ./fixtures/simple-local;
        };
      };
    in
    assert' "input_override" (
      result.outputs.simpleValue == "hello from simple-local"
      && toString result.outputs.simplePath == overridePath
      # A path, so a build that interpolates it gets a store copy.
      && builtins.isPath result.outputs.simplePath
    ) "Expected simplePath to be '${overridePath}', got: ${toString result.outputs.simplePath}";

  # Test 5: Dependency values are accessible
  test_dependency_values =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides = {
          self = ./fixtures/with-dep;
          simple = ./fixtures/simple-local;
        };
      };
    in
    assert' "dependency_values" (
      result.outputs.simpleValue == "hello from simple-local"
    ) "Expected simpleValue to be 'hello from simple-local', got: ${result.outputs.simpleValue}";

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

  # Test 7: Lockless flake works with default (in place)
  test_lockless_default =
    let
      result = flake-compatish { source = ./fixtures/lockless; };
    in
    assert' "lockless_default" (result.outputs.selfPath == ./fixtures/lockless)
      "Expected selfPath to be the source itself for lockless default, got: ${toString result.outputs.selfPath}";

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
      "Expected simplePath to be in /nix/store when using string flake ref, got: ${toString result.outputs.simplePath}";

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

  # Test 12: Nonexistent path override for self falls back to the source
  test_nonexistent_self_override_fallback =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides = {
          self = /nonexistent/path/that/does/not/exist;
        };
      };
    in
    assert' "nonexistent_self_override_fallback" (result.outputs.selfPath == ./fixtures/simple)
      "Expected selfPath to be the source after fallback, got: ${toString result.outputs.selfPath}";

  # Test 12a: A lookup path that NIX_PATH does not name falls back to the
  # lockfile, so `overrides.nixpkgs = <nixpkgs>` is safe on every machine
  test_missing_lookup_override_fallback =
    let
      result = flake-compatish {
        source = ./fixtures/with-dep;
        overrides.simple = <flake-compatish-test-not-in-nix-path>;
      };
    in
    assert' "missing_lookup_override_fallback" (result.outputs.simpleValue == "hello from simple")
      "Expected simpleValue from the lockfile, got: ${result.outputs.simpleValue}";

  # Test 12b: A store path string keeps its context, so a build does not
  # copy it again.
  test_store_source_keeps_context =
    let
      stored = builtins.path {
        path = ./fixtures/simple;
        name = "simple";
      };
      result = flake-compatish { source = stored; };
    in
    assert' "store_source_keeps_context" (
      result.outputs.selfPath == stored
      && builtins.getContext result.outputs.selfPath == builtins.getContext stored
    ) "Expected selfPath to be ${stored} with context, got: ${toString result.outputs.selfPath}";

  storedSimpleLocal = builtins.path {
    path = ./fixtures/simple-local;
    name = "simple-local";
  };

  # Test 12c: An override can be a store path string, a store path value or
  # an evaluated flake. Each is used in place: no fetch, no second copy.
  test_store_overrides_in_place =
    let
      withSimple =
        simple:
        (flake-compatish {
          source = ./fixtures/with-dep;
          overrides.simple = simple;
        }).outputs;
      fromString = withSimple storedSimpleLocal;
      fromPath = withSimple (/. + builtins.unsafeDiscardStringContext storedSimpleLocal);
      flake = (flake-compatish storedSimpleLocal).outputs;
      fromFlake = withSimple flake;
    in
    assert' "store_overrides_in_place" (
      fromString.simpleValue == "hello from simple-local"
      && fromString.simplePath == storedSimpleLocal
      && builtins.getContext fromString.simplePath == builtins.getContext storedSimpleLocal
      && builtins.isPath fromPath.simplePath
      && toString fromPath.simplePath == storedSimpleLocal
      && fromFlake.simpleValue == "hello from simple-local"
      && fromFlake.simplePath == storedSimpleLocal
    ) "Expected each store override at ${storedSimpleLocal}, got: ${toString fromString.simplePath}, ${toString fromPath.simplePath}, ${toString fromFlake.simplePath}";

  # Test 12d: A source can be an evaluated flake, or an attrset with
  # `outPath` and `sourceInfo`, which then keeps that sourceInfo.
  test_attrset_source =
    let
      flake = (flake-compatish storedSimpleLocal).outputs;
      fromFlake = (flake-compatish { source = flake; }).outputs;
      tree = builtins.fetchTree {
        type = "path";
        path = toString ./fixtures;
      };
      withInfo =
        (flake-compatish {
          source = {
            outPath = tree.outPath + "/simple-local";
            sourceInfo = tree;
          };
        }).outputs;
    in
    assert' "attrset_source" (
      fromFlake.testValue == "hello from simple-local"
      && fromFlake.outPath == storedSimpleLocal
      && withInfo.testValue == "hello from simple-local"
      && withInfo.sourceInfo.narHash == tree.narHash
      && withInfo.outPath == tree.outPath + "/simple-local"
    ) "Expected the attrset sources to evaluate in place, got: ${toString fromFlake.outPath}, ${toString withInfo.outPath}";

  # Test 12e: An evaluated flake in a subdirectory, as an override, names that
  # directory and keeps its tree's sourceInfo.
  test_subdir_flake_override =
    let
      tree = builtins.fetchTree {
        type = "path";
        path = toString ./fixtures;
      };
      sub =
        (flake-compatish {
          source = {
            outPath = tree.outPath + "/simple-local";
            sourceInfo = tree;
          };
        }).outputs;
      result =
        (flake-compatish {
          source = ./fixtures/with-dep;
          overrides.simple = sub;
        }).outputs;
    in
    assert' "subdir_flake_override" (
      result.simpleValue == "hello from simple-local"
      && result.simplePath == tree.outPath + "/simple-local"
      && result.inputs.simple.sourceInfo == tree
    ) "Expected simple at ${tree.outPath}/simple-local, got: ${toString result.simplePath}";

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
      toString result.outputs.simplePath == "${fixturesPath}/simple"
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
          simple = ./fixtures/simple-local;
        };
      };
    in
    assert' "override_misses_nested" (
      result.outputs.nestedSimpleValue == "hello from simple"
      && toString result.outputs.nestedSimplePath == "${fixturesPath}/simple"
    )
      "Expected the nested simple to come from the lockfile, got: ${toString result.outputs.nestedSimplePath}";

  # Test 20: reroot reaches it, because the key is the input name that
  # with-dep uses and not the node the lockfile named.
  test_reroot_reaches_nested =
    let
      simple = (flake-compatish {
        source = ./fixtures/simple-local;
        overrides.self = ./fixtures/simple-local;
      }).outputs;
      result = flake-compatish {
        source = ./fixtures/deep;
        overrides.self = ./fixtures/deep;
        reroot = { inherit simple; };
      };
    in
    assert' "reroot_reaches_nested" (
      result.outputs.nestedSimpleValue == "hello from simple-local"
      && toString result.outputs.nestedSimplePath == fixturesPath + "/simple-local"
    ) "Expected the nested simple to be the local one, got: ${toString result.outputs.nestedSimplePath}";

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
    test_default_in_place
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
    test_missing_lookup_override_fallback
    test_store_source_keeps_context
    test_store_overrides_in_place
    test_attrset_source
    test_subdir_flake_override
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
