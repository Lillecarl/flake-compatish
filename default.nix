# flake-compatish: Evaluate flakes without the flake evaluator
#
# A pure-Nix implementation that reads flake.nix and flake.lock to produce
# flake outputs. Requires builtins.fetchTree (Nix 2.4+).
#
# Usage:
#   # Minimal - copies source to store (flake-compatible purity)
#   import flake-compatish ./.
#
#   # With overrides - use local paths or flake refs
#   import flake-compatish {
#     source = ./.;
#     overrides = {
#       self = ./.;                                  # path: use directly, no store copy
#       nixpkgs = ~/Code/nixpkgs;                    # path: local checkout
#       nixpkgs = "github:nixos/nixpkgs/master";     # string: parsed as flake ref
#     };
#   }
#
#   # With reroot - use an already-evaluated flake for an input, at any depth
#   import flake-compatish {
#     source = ./.;
#     reroot = { nanopynix = <an evaluated flake>; };
#   }
#
# Set FLAKE_COMPATISH_DISABLE_OVERRIDES=1 in the environment to ignore every
# override and evaluate straight from the lockfile.
#
# `compatish` holds the lib.nix result for the same evaluation: chainable
# overrides and strict override names. See lib.nix.
args:
let
  evaluated = import ./nix/core.nix args;
in
evaluated.compat // { compatish = import ./nix/overridable.nix evaluated; }
