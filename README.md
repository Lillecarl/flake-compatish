# flake-compatish

Evaluate a flake without the flake evaluator. flake-compatish reads
`flake.nix` and `flake.lock` in plain Nix and calls `outputs` itself.

## Why

The flake evaluator copies your source to the Nix store before it evaluates
anything. On a large tree, or when you work on a dependency such as nixpkgs,
every change costs a copy.

flake-compatish lets you:

- **Keep `flake.nix`** for CI and for other people. The flake stays a normal
  flake.
- **Skip the store copy** on your own machine. Evaluation reads your working
  directory.
- **Point inputs at local checkouts** without an edit to `flake.lock`.
- **Replace a whole flake anywhere in the graph**, including copies of it that
  `follows` cannot reach.

## Requirements

- `builtins.fetchTree`, which needs Nix 2.4 or later with flakes enabled.
- `builtins.parseFlakeRef`, but only when you give a flake reference as a
  string.

## Quick start

Add flake-compatish as an input of your flake:

```nix
{
  inputs.flake-compatish.url = "github:Lillecarl/flake-compatish";
  # ...
}
```

Then write a `default.nix` next to `flake.nix`. It fetches flake-compatish at
the revision your lockfile pins:

```nix
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compatish = builtins.fetchTree lock.nodes.flake-compatish.locked;
in
import flake-compatish ./.
```

Build with the non-flake CLI:

```bash
nix build --file . outputs.packages.x86_64-linux.default
nix build --file . impure.packages.default   # current system selected for you
```

## Two ways to call it

`default.nix` takes a path or an attrset. The two forms differ in one thing:
the store copy.

| call | `self` comes from | store copy |
| --- | --- | --- |
| `import flake-compatish ./.` | the directory itself | no |
| `import flake-compatish { source = ./.; }` | a store copy of `source` | yes, as the flake evaluator does |

The path form is short for `{ source = ./.; overrides.self = ./.; }`. Use the
attrset form when you need any other argument, and add `overrides.self = ./.;`
yourself if you still want to skip the copy.

## Arguments

| argument | default | effect |
| --- | --- | --- |
| `source` | required | The flake to evaluate. A path, or a flake reference string such as `"github:owner/repo"`. |
| `overrides` | `{ }` | Replace the source of an input. See [Override an input's source](#override-an-inputs-source). |
| `overridesFile` | `source + "/overrides.nix"` | The optional machine-local override file. See [Local overrides](#local-overrides). |
| `warnOverrides` | `true` | Print an evaluation warning for each override that applies. |
| `reroot` | `{ }` | Replace an evaluated flake at any depth. See [Replace a flake](#replace-a-flake-reroot). |
| `nixpkgsArgs` | `null` | Configure one shared nixpkgs per system. See [Shared package sets](#shared-package-sets-experimental). |

`lib.nix` takes one more, `strict`. See [Strict names](#strict-names).

## Output

```nix
{
  outputs   = { packages, ... };   # the root flake
  inputs    = { self, nixpkgs, ... };
  impure    = { packages, ... };   # outputs with builtins.currentSystem selected
  compatish = { ... };             # the lib.nix result, see below
}
```

- `outputs` is the root flake as another flake would see it: its outputs,
  plus `outPath`, `sourceInfo`, `inputs`, `outputs` and `_type = "flake"`.
- `inputs` holds the root's resolved inputs, and `self`.
- `impure` takes each top-level attribute of `outputs` and selects
  `.${builtins.currentSystem}` where it exists. `impure.packages.hello` is
  `outputs.packages.x86_64-linux.hello` on an x86_64 Linux machine. It needs
  impure evaluation, which `nix build --file` gives by default.
- `compatish` is described in [Overridable results](#overridable-results-libnix).

## Override an input's source

`overrides` replaces where an input's source comes from. The input keeps the
inputs that `flake.lock` gives it.

```nix
import flake-compatish {
  source = ./.;
  overrides = {
    self = ./.;                                 # the root itself
    nixpkgs = ~/Code/nixpkgs;                   # a path: used in place, no copy
    home-manager = "github:nix-community/home-manager/master";  # a string: fetched
  };
}
```

- **A path** is used in place. Nix does not copy it to the store, so an edit
  shows up on the next evaluation.
- **A string** is a flake reference. flake-compatish parses it and fetches it.
- **`self`** names the root flake.
- **Other names** must be inputs of the root flake. flake-compatish ignores any
  other name and does not evaluate its value, so a typo goes unnoticed. Use
  `lib.nix` if you want an error instead.
- **A path that does not exist** falls back to the lockfile, with no warning.
  So one `default.nix` can name a checkout that only some machines have.

An override replaces the lockfile node with that name. Every flake in the
graph that uses that node sees the override. A second copy of the same
dependency has a suffixed node name, such as `nixpkgs_2`, and an override does
not reach it. Use `follows` in `flake.nix`, or use `reroot`.

### Local overrides

Machine-local checkouts belong in a file that git ignores. Put
`overrides.nix` next to `flake.nix`:

```nix
{
  nixpkgs = ~/Code/nixpkgs;
}
```

And add it to `.gitignore`:

```
overrides.nix
```

flake-compatish looks for this file relative to `source`. `overridesFile`
picks a different path.

- flake-compatish reads the file only during impure evaluation. It tests this
  with the `HOME` and `USER` environment variables, which pure evaluation does
  not see. The flake evaluator therefore never applies it, even when a dirty
  tree copied it into the store.
- The same name rules apply as for `overrides`.
- A local value wins over the same name in `overrides`. If the local value
  cannot be used, for example a path that does not exist, the `overrides` value
  applies. If neither can be used, the lockfile applies.

### Warnings

Each override that applies prints one line:

```
evaluation warning: flake-compatish: /home/me/project: overriding nixpkgs to /home/me/Code/nixpkgs
```

The first path is the root `source`. Pass
`warnOverrides = false;` to turn the warnings off.

### Disable every override

Set `FLAKE_COMPATISH_DISABLE_OVERRIDES` to anything other than empty or `0`:

```bash
FLAKE_COMPATISH_DISABLE_OVERRIDES=1 nix build --file . impure.packages.hello
```

flake-compatish then ignores `overrides`, the local file, `self` and `reroot`,
and evaluates from the lockfile alone. The source is copied to the store, as
the flake evaluator does. Use it to check whether a local checkout causes a
result, with no edit to any file. `nixpkgsArgs` still applies.

## Replace a flake: `reroot`

`overrides` changes a source and keeps the lockfile's view of that input's own
inputs. That is not enough two levels down. If your flake uses `easykubenix`,
and `easykubenix` uses `nanopynix`, the lockfile can hold a second `nanopynix`
node. No override reaches it.

`reroot` replaces the evaluated flake instead. You evaluate it yourself, with
whatever inputs you want, and flake-compatish uses it wherever the graph has
an input of that name:

```nix
let
  nanopynix = (import flake-compatish ~/Code/nanopynix).outputs;
in
import flake-compatish {
  source = ./.;
  reroot = { inherit nanopynix; };
}
```

- The key is the **input name**, not the node name. That is why it reaches
  `nanopynix_2`: the node has a suffix, and the input that names it does not.
- It applies at **every depth**, root included. No `follows` is needed.
- An input declared `flake = false` is not rerooted. It is a plain source, and
  the flake that declares it reads it as a path.
- flake-compatish passes the value on as it is. Give it what the consuming
  flakes read: usually `outPath` and the outputs.
  `(import flake-compatish …).outputs` has the full shape of an evaluated
  flake.

### A function as the value

A `reroot` value can also be a function. It gets the flake that would have
been used, and returns the replacement:

```nix
import flake-compatish {
  source = ./.;
  reroot.nixpkgs = prev: prev // {
    legacyPackages = builtins.mapAttrs (system: _:
      import prev.outPath { inherit system; config.allowUnfree = true; }
    ) prev.legacyPackages;
  };
}
```

flake-compatish calls the function once for each pair of input name and
lockfile node, not once for each place the input appears. Two copies of
nixpkgs give two calls; one copy shared by ten flakes gives one.

## Shared package sets (experimental)

`nixpkgsArgs` gives every compatible flake in the graph the same configured
nixpkgs, one per system:

```nix
import flake-compatish {
  source = ./.;
  nixpkgsArgs = system: {
    inherit system;
    config.allowUnfree = true;
  };
}
```

flake-compatish imports the root's `nixpkgs` input once for each system that
input exposes. Then it replaces `self.legacyPackages` in each other flake that
already has a `legacyPackages` output, for the systems that output already
has. A compatible flake builds its packages from
`inputs.self.legacyPackages.${system}`.

The root flake must have an input named `nixpkgs`, or evaluation aborts.

This is not the same as a `reroot.nixpkgs` function. `reroot` replaces the
`nixpkgs` input that a flake receives. `nixpkgsArgs` replaces each flake's own
`self.legacyPackages`.

## What the lockfile can hold

- Lockfile versions 5, 6 and 7. Another version aborts with an error.
- A flake without `flake.lock`, which has no inputs except `self`.
- `follows`, at any depth.
- A flake in a subdirectory, `?dir=sub`.
- Inputs with `flake = false`. They arrive as a source, not as a flake.
- A relative `path:` input, such as `path:../sibling`. flake-compatish
  resolves it against the directory of the flake that declares it, not
  against a store copy. An override of that flake does not move the relative
  input: `../sibling` still means the sibling the lockfile named, as with the
  flake evaluator.

## Overridable results: `lib.nix`

`default.nix` stays a plain flake-compat shim. `lib.nix` gives a result that
you can override again after import. The idea comes from
[sprinkles](https://git.afnix.fr/sprinkles/sprinkles).

```nix
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compatish = builtins.fetchTree lock.nodes.flake-compatish.locked;
in
(import "${flake-compatish}/lib.nix").new ./.
```

`new` takes the same arguments as `default.nix`, plus `strict`. The result has
`inputs`, `outputs` and `impure`, and also:

| attribute | value |
| --- | --- |
| `args` | the arguments this result was evaluated with |
| `sources` | the root's inputs as fetched: after `overrides`, before `reroot` |
| `override` | evaluates again with changed arguments |

You do not need `lib.nix` to get this. `default.nix` returns the same result
as `compatish`, from the same evaluation, and computes it only when you read
it:

```nix
(import ./.).compatish.override { overrides.nixpkgs = ~/Code/nixpkgs; }
```

### `override`

An attrset merges into the arguments. `overrides` and `reroot` merge key by
key, so each call adds to the one before:

```bash
nix build --impure --expr '
  (((import ./.).compatish
    .override { overrides.nixpkgs = ~/Code/nixpkgs; })
    .override { overrides.home-manager = ~/Code/home-manager; })
    .impure.packages.default'
```

A function gets the previous arguments and returns an attrset to merge with
`//`. Use it to remove a key:

```nix
flake.override (prev: { overrides = removeAttrs prev.overrides [ "nixpkgs" ]; })
```

`override` needs the `overrides.` prefix because input names are free-form.
An input can be named `source` or `strict`, so a flat
`override { nixpkgs = …; }` could not tell an input from an argument.

### Compose projects

When a project's `default.nix` uses flake-compatish, another project can take
a configured copy of it at any depth:

```nix
import flake-compatish {
  source = ./.;
  reroot.mylib = _:
    ((import ~/Code/mylib).compatish.override {
      overrides.nixpkgs = ~/Code/nixpkgs;
    }).outputs;
}
```

### Strict names

Through `lib.nix` or `compatish`, an unknown name aborts evaluation:

```
error: flake-compatish: no input to reroot named `simpel`; known: `nixpkgs`, `simple`, `with-dep`
```

- An `overrides` name must be `self` or an input of the root flake.
- A `reroot` name must be an input that some flake in the graph declares.
- The local `overrides.nix` is never checked. It belongs to the machine, not
  to the project.

Pass `strict = false;` to ignore unknown names, as `default.nix` does.
`default.nix` stays lenient even when you read `compatish`: only reads through
`compatish` see the check.

## API reference

Every function carries a [nixdoc](https://github.com/nix-community/nixdoc)
comment. Generate the reference as Markdown:

```bash
nix build --file ./doc && cat result
```

It covers `default.nix`, `lib.nix`, and the attributes that the internal
`nix/core.nix` and `nix/overridable.nix` return. nixdoc does not extract
`let` bindings, so the comments on internal helpers are for readers of the
source.

## Running tests

```bash
./test/integration.sh
```
