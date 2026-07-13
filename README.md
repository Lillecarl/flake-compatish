# flake-compatish

Evaluate flakes without the flake evaluator. Requires Nix 2.4+ with `builtins.fetchTree`.

## Why

Flakes copy your source to the Nix store before evaluation. For large projects or when hacking on dependencies like nixpkgs, this creates painful iteration cycles.

flake-compatish lets you:
- **Keep flake.nix for CI/others** - maintain full flake compatibility
- **Skip the store copy locally** - evaluate directly from your working directory
- **Override inputs on the fly** - point dependencies at local checkouts without touching flake.lock

## Usage

Add flake-compatish as a flake input, then create a `default.nix`:

```nix
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compatish = builtins.fetchTree lock.nodes.flake-compatish.locked;
in
import flake-compatish { source = ./.; }
```

### With overrides

```nix
import flake-compatish {
  source = ./.;
  overrides = {
    # Path: use directly without store copy (fast local dev)
    self = ./.;
    nixpkgs = ~/Code/nixpkgs;

    # String: parsed as flake ref and fetched
    nixpkgs = "github:nixos/nixpkgs/nixos-unstable";
  };
}
```

### Local overrides

For machine-local development checkouts, put an `overrides.nix` file next to
the consuming flake's `flake.nix` and add it to that repository's `.gitignore`:

```nix
{
  nixpkgs = ~/Code/nixpkgs;
}
```

flake-compatish finds this file relative to the supplied `source`. Pass
`overridesFile = /path/to/another-overrides.nix;` to use a different optional
file. It is applied in impure evaluation when available; pure flake evaluation
silently ignores it. Only `self` and inputs declared by the consumer's
lockfile are considered. Missing or unavailable path overrides fall back to
the lockfile.

### Output structure

```nix
{
  inputs = { self, nixpkgs, ... };  # resolved inputs
  outputs = { packages, ... };      # flake outputs
  impure = { packages, ... };       # outputs with current system auto-selected
}
```

## Running tests

```bash
./test/integration.sh
```
