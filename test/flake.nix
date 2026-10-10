{
  inputs = {
    flake-compatish.url = "path:../";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { flake-compatish, ... }: {
    # overrides.nix is gitignored in this fixture.  A pure flake evaluation
    # therefore sees the copied fixture without that local file.
    pureLocalOverride =
      let
        result = import flake-compatish {
          source = ./fixtures/with-dep;
          overrides = {
            self = ./fixtures/with-dep;
            simple = ./fixtures/simple;
          };
          overridesFile = ./fixtures/with-dep/custom-overrides.nix;
        };
      in
      if
        result.outputs.simpleValue == "hello from simple"
        && builtins.substring 0 11 result.outputs.simplePath == "/nix/store/"
      then
        "pure local overrides ignored"
      else
        throw "local override was unexpectedly applied during pure evaluation";

    # Pure evaluation sees an empty NIX_PATH, and an explicit value is gated
    # the same way as the local file. Pure fetchTree refuses an unlocked
    # path, so `simple` comes from `overrides`, which a system-wide override
    # would beat.
    pureSystemOverride =
      let
        result = import flake-compatish {
          source = ./fixtures/with-dep;
          overrides = {
            self = ./fixtures/with-dep;
            simple = ./fixtures/simple;
          };
          systemOverrides = ./fixtures/system-overrides.nix;
        };
      in
      if result.outputs.simpleValue == "hello from simple" then
        "pure system overrides ignored"
      else
        throw "system-wide override was unexpectedly applied during pure evaluation";

    # Nix rejects `~` while parsing in pure mode, and `tryEval` cannot catch
    # it, so this evaluates only if the local file is never read.
    pureTildeFileNotRead =
      let
        result = import flake-compatish {
          source = ./fixtures/with-dep;
          overrides = {
            self = ./fixtures/with-dep;
            simple = ./fixtures/simple;
          };
          overridesFile = ./fixtures/tilde-overrides.nix;
        };
      in
      if result.outputs.simpleValue == "hello from simple" then
        "pure tilde file not read"
      else
        throw "the local file was applied during pure evaluation";
  };
}
