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
the lockfile. Applied overrides emit evaluation warnings by default; pass
`warnOverrides = false;` to suppress them.

### Disabling overrides

Set `FLAKE_COMPATISH_DISABLE_OVERRIDES` to any value other than empty or `0` to
ignore every override — supplied, local file, and `self` alike — and evaluate
straight from the lockfile:

```bash
FLAKE_COMPATISH_DISABLE_OVERRIDES=1 nix build -f . packages.hello
```

This is a quick way to check whether a local checkout is responsible for a
build result without editing any expressions. The source is copied to the store
as it would be under the flake evaluator.

### Shared package sets (experimental)

Pass `nixpkgsArgs` to configure one package set per system. flake-compatish
imports the root nixpkgs input once per existing system and makes the resulting
sets available as `self.legacyPackages` to compatible flakes in the graph:

```nix
import flake-compatish {
  source = ./.;
  nixpkgsArgs = system: {
    inherit system;
    config.allowUnfree = true;
  };
}
```

Compatible flakes should construct their packages from
`inputs.self.legacyPackages.${system}`. Only flakes that already expose
`legacyPackages` are changed, and only for systems they already expose. When
omitted, flake-compatish leaves each flake's own `legacyPackages` output
unchanged.

### Output structure

```nix
{
  inputs = { self, nixpkgs, ... };  # resolved inputs
  outputs = { packages, ... };      # flake outputs
  impure = { packages, ... };       # outputs with current system auto-selected
}
```

## The involved entrypoint: `lib.nix`

`default.nix` is a flake-compat shim and stays one. `lib.nix` evaluates the
same flake the same way, and returns a result you can override again after
import. The idea comes from [sprinkles](https://git.afnix.fr/sprinkles/sprinkles).

Use it from the consumer's `default.nix`:

```nix
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compatish = builtins.fetchTree lock.nodes.flake-compatish.locked;
in
(import "${flake-compatish}/lib.nix").new ./.
```

The result has `inputs`, `outputs` and `impure` as before, plus `args`,
`sources` and `override`.

### Override after import

An attrset merges into the arguments. `overrides` and `reroot` merge key by
key, so each call adds to the previous one:

```bash
nix build --impure --expr '
  ((import ./.).override { overrides.nixpkgs = ~/Code/nixpkgs; })
    .impure.packages.default'
```

A function gets the previous arguments and returns the attrset to merge with
`//`. Use it to remove a key:

```nix
flake.override (prev: { overrides = removeAttrs prev.overrides [ "nixpkgs" ]; })
```

### Reroot with a function

A `reroot` value can be a function. It gets the flake that would have been
used, and returns the one to use. This configures nixpkgs everywhere the
graph names it `nixpkgs`:

```nix
(import "${flake-compatish}/lib.nix").new {
  source = ./.;
  reroot.nixpkgs = prev: prev // {
    legacyPackages = builtins.mapAttrs (system: _:
      import prev.outPath { inherit system; config.allowUnfree = true; }
    ) prev.legacyPackages;
  };
}
```

flake-compatish calls the function once for each input name and lockfile
node, not once for each edge.

This replaces the `nixpkgs` *input*. It is not the same as `nixpkgsArgs`, which
replaces each flake's own `self.legacyPackages`.

### Compose projects

When a project's `default.nix` returns `lib.nix` output, another project can
use a configured copy of it at any depth:

```nix
(import "${flake-compatish}/lib.nix").new {
  source = ./.;
  reroot.mylib = _:
    ((import ~/Code/mylib).override { overrides.nixpkgs = ~/Code/nixpkgs; }).outputs;
}
```

### Strict names

`lib.nix` aborts on an `overrides` name that is not `self` or a root input,
and on a `reroot` name that no flake in the graph declares. The error lists
the names it knows. Pass `strict = false;` to ignore unknown names, as
`default.nix` does. A local `overrides.nix` is never checked.

## Running tests

```bash
./test/integration.sh
```
