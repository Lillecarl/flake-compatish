# This test is run after test/integration.sh copies overrides.nix.in to the
# gitignored consumer-local overrides.nix.
let
  flake-compatish = import ../.;
  fixturesPath = builtins.toString ./fixtures;
  result = flake-compatish {
    source = ./fixtures/with-dep;
    overrides.self = ./fixtures/with-dep;
  };
in
if result.outputs.simplePath == "${fixturesPath}/simple" then
  "impure local override applied"
else
  throw "expected the local override to use ${fixturesPath}/simple, got ${result.outputs.simplePath}"
