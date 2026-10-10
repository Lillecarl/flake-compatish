# Tests for lib.nix. Run with: nix eval --impure --file ./test/lib.nix
let
  fc = import ../lib.nix;

  isStorePath = path: builtins.substring 0 11 (builtins.toString path) == "/nix/store/";

  assert' =
    name: condition: message:
    if condition then true else builtins.throw "FAILED: ${name} - ${message}";

  fixturesPath = builtins.toString ./fixtures;

  fails = value: !(builtins.tryEval value).success;

  withDep = fc.new {
    source = ./fixtures/with-dep;
    overrides.self = ./fixtures/with-dep;
  };

  test_path_argument =
    let
      result = fc.new ./fixtures/simple;
    in
    assert' "path_argument" (
      result.outputs.testValue == "hello from simple" && !(isStorePath result.outputs.selfPath)
    ) "Expected a path argument to override self, as default.nix does";

  # `overrides` merges key by key, so the earlier `self` survives.
  test_override_merges =
    let
      result = withDep.override { overrides.simple = ./fixtures/simple; };
    in
    assert' "override_merges"
      (result.outputs.simplePath == "${fixturesPath}/simple" && !(isStorePath result.outputs.selfPath))
      "Expected both overrides to apply, got simple=${result.outputs.simplePath} self=${result.outputs.selfPath}";

  test_override_chains =
    let
      result = (withDep.override { overrides.simple = ./fixtures/simple; }).override {
        warnOverrides = false;
      };
    in
    assert' "override_chains" (
      result.outputs.simplePath == "${fixturesPath}/simple" && result.args.warnOverrides == false
    ) "Expected a second override to keep the first";

  test_override_function_removes =
    let
      result = (withDep.override { overrides.simple = ./fixtures/simple; }).override (prev: {
        overrides = removeAttrs prev.overrides [ "simple" ];
      });
    in
    assert' "override_function_removes" (isStorePath result.outputs.simplePath)
      "Expected simple to come from the lockfile again, got: ${result.outputs.simplePath}";

  test_sources =
    let
      result = withDep.override { overrides.simple = ./fixtures/simple; };
    in
    assert' "sources" (
      result.sources.simple.outPath == "${fixturesPath}/simple"
      && isStorePath result.sources.nixpkgs.outPath
    ) "Expected sources to show the override and the lockfile, got: ${result.sources.simple.outPath}";

  test_strict_rejects_override_typo = assert' "strict_rejects_override_typo" (fails
    (withDep.override {
      overrides.simpel = ./fixtures/simple;
    }).outputs
  ) "Expected an unknown override name to abort";

  test_strict_rejects_reroot_typo = assert' "strict_rejects_reroot_typo" (fails
    (withDep.override {
      reroot.simpel = { };
    }).outputs
  ) "Expected an unknown reroot name to abort";

  # `simple` is not a root input of deep, but with-dep declares it.
  test_strict_accepts_nested_reroot = assert' "strict_accepts_nested_reroot" (
    !(fails
      (fc.new {
        source = ./fixtures/deep;
        reroot.simple = prev: prev;
      }).outputs.nestedSimpleValue
    )
  ) "Expected a reroot name declared below the root to pass";

  test_lenient_ignores_typo =
    let
      result = withDep.override {
        strict = false;
        overrides.simpel = throw "unknown override was forced";
      };
    in
    assert' "lenient_ignores_typo" (
      result.outputs.testValue == "hello from with-dep"
    ) "Expected strict = false to ignore unknown names, as default.nix does";

  test_reroot_function =
    let
      result = fc.new {
        source = ./fixtures/deep;
        reroot.simple = prev: prev // { testValue = "wrapped ${prev.testValue}"; };
      };
    in
    assert' "reroot_function" (
      result.outputs.nestedSimpleValue == "wrapped hello from simple"
    ) "Expected the function to wrap the lockfile's simple, got: ${result.outputs.nestedSimpleValue}";

  # The general form of nixpkgsArgs: import the input's own source with
  # other arguments.
  test_reroot_function_configures_package_set =
    let
      result = withDep.override {
        overrides.nixpkgs = ./fixtures/fake-nixpkgs;
        reroot.nixpkgs =
          prev:
          prev
          // {
            legacyPackages = builtins.mapAttrs (
              system: _:
              import prev.outPath {
                inherit system;
                marker = "rerooted";
              }
            ) prev.legacyPackages;
          };
      };
    in
    assert' "reroot_function_configures_package_set"
      (result.inputs.nixpkgs.legacyPackages.x86_64-linux.marker == "rerooted")
      "Expected the rerooted package set, got: ${result.inputs.nixpkgs.legacyPackages.x86_64-linux.marker}";

  # The README's composition example: a lib.nix result, overridden, used two
  # levels down.
  test_compose =
    let
      simple = (fc.new { source = ./fixtures/simple; }).override { overrides.self = ./fixtures/simple; };
      result = fc.new {
        source = ./fixtures/deep;
        reroot.simple = _: simple.outputs;
      };
    in
    assert' "compose" (
      result.outputs.nestedSimplePath == "${fixturesPath}/simple"
    ) "Expected the overridden simple two levels down, got: ${result.outputs.nestedSimplePath}";

  allTests = [
    test_compose
    test_path_argument
    test_override_merges
    test_override_chains
    test_override_function_removes
    test_sources
    test_strict_rejects_override_typo
    test_strict_rejects_reroot_typo
    test_strict_accepts_nested_reroot
    test_lenient_ignores_typo
    test_reroot_function
    test_reroot_function_configures_package_set
  ];
in
if builtins.all (x: x) allTests then
  "All ${toString (builtins.length allTests)} lib tests passed!"
else
  builtins.throw "Some tests failed"
