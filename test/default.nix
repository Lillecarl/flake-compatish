# Test suite for flake-compatish
# Run with: nix eval --impure --file ./test/test.nix
let
  flake-compatish = import ../.;

  # Helper to check if path is in nix store
  isStorePath = path: builtins.substring 0 11 (builtins.toString path) == "/nix/store/";

  # Helper to run assertion with descriptive error
  assert' = name: condition: message:
    if condition then true
    else builtins.throw "FAILED: ${name} - ${message}";

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
    assert' "default_copies_to_store"
      (isStorePath result.outputs.selfPath)
      "Expected selfPath to be in /nix/store, got: ${result.outputs.selfPath}";

  # Test 2: overrides.self - source should NOT be copied to store
  test_override_self_no_store =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "override_self_no_store"
      (!(isStorePath result.outputs.selfPath))
      "Expected selfPath to NOT be in /nix/store, got: ${result.outputs.selfPath}";

  # Test 3: Outputs are correctly resolved
  test_outputs_resolved =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "outputs_resolved"
      (result.outputs.testValue == "hello from simple")
      "Expected testValue to be 'hello from simple', got: ${result.outputs.testValue}";

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
    assert' "input_override"
      (result.outputs.simplePath == overridePath)
      "Expected simplePath to be '${overridePath}', got: ${result.outputs.simplePath}";

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
    assert' "dependency_values"
      (result.outputs.simpleValue == "hello from simple")
      "Expected simpleValue to be 'hello from simple', got: ${result.outputs.simpleValue}";

  # Test 6: Lockless flake works with override
  test_lockless_with_override =
    let
      result = flake-compatish {
        source = ./fixtures/lockless;
        overrides.self = ./fixtures/lockless;
      };
    in
    assert' "lockless_with_override"
      (result.outputs.testValue == "hello from lockless")
      "Expected testValue to be 'hello from lockless', got: ${result.outputs.testValue}";

  # Test 7: Lockless flake works with default (store copy)
  test_lockless_default =
    let
      result = flake-compatish { source = ./fixtures/lockless; };
    in
    assert' "lockless_default"
      (isStorePath result.outputs.selfPath)
      "Expected selfPath to be in /nix/store for lockless default, got: ${result.outputs.selfPath}";

  # Test 8: inputs attrset contains self
  test_inputs_has_self =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "inputs_has_self"
      (result.inputs ? self)
      "Expected inputs to contain 'self' attribute";

  # Test 9: _type is "flake"
  test_flake_type =
    let
      result = flake-compatish {
        source = ./fixtures/simple;
        overrides.self = ./fixtures/simple;
      };
    in
    assert' "flake_type"
      (result.outputs._type == "flake")
      "Expected _type to be 'flake', got: ${result.outputs._type}";

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
    assert' "string_override_fetches"
      (isStorePath result.outputs.simplePath)
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
    assert' "string_override_values"
      (result.outputs.simpleValue == "hello from simple")
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
    assert' "nonexistent_self_override_fallback"
      (isStorePath result.outputs.selfPath)
      "Expected selfPath to be in /nix/store after fallback, got: ${result.outputs.selfPath}";

  # Collect all tests
  allTests = [
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
  ];

  # Run all tests - if any fail, the whole eval fails with a descriptive error
  runTests = builtins.all (x: x) allTests;

in
if runTests then
  "All ${toString (builtins.length allTests)} tests passed!"
else
  builtins.throw "Some tests failed"
