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
import flake-compatish ./.
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
nix eval --impure --file ./test
```
