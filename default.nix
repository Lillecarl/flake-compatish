/**
  Evaluate a flake without the flake evaluator. flake-compatish reads
  `flake.nix` and `flake.lock` and calls `outputs` itself.

  # Inputs

  `args`
  : A path, or an attrset. A path `p` is short for
    `{ source = p; overrides.self = p; }`, which evaluates `p` in place with
    no store copy.

    `source`
    : The flake to evaluate: a path, or a flake reference string.

    `overrides` (default `{ }`)
    : Input name to a path, used in place, or a flake reference string,
      fetched. `self` names the root. A name that is not `self` or a root
      input is ignored and not evaluated. A path that does not exist falls
      back to the lockfile.

    `overridesFile` (default `source + "/overrides.nix"`)
    : An optional machine-local file of the same shape. It is read only in
      impure evaluation, and it wins over `overrides`.

    `systemOverrides` (default `true`)
    : The machine's overrides, matched by flake reference and not by name,
      at every depth. `true` reads the file the NIX_PATH entry
      `flake-compatish-overrides` names, `false` reads nothing, and a path,
      attrset or function is used instead. Impure evaluation only. It wins
      over `overrides` and loses to the local file.

    `warnOverrides` (default `true`)
    : Print a warning for each override that applies.

    `reroot` (default `{ }`)
    : Input name to an evaluated flake, or to a function from the flake that
      would have been used to its replacement. It applies at every depth.

    `nixpkgsArgs` (default `null`)
    : A function from a system to the arguments for the root `nixpkgs`
      input. The result replaces `self.legacyPackages` in compatible flakes.

  Set `FLAKE_COMPATISH_DISABLE_OVERRIDES=1` to ignore `overrides`, the local
  file, the system-wide overrides and `reroot`, and evaluate from the
  lockfile alone.

  # Output

  `outputs`
  : The root flake, as another flake would see it.

  `inputs`
  : The root's resolved inputs, and `self`.

  `impure`
  : `outputs`, with `builtins.currentSystem` selected in each attribute
    that has it.

  `compatish`
  : The `lib.nix` result for the same evaluation: `override`, `args` and
    `sources`, with strict name checks. Evaluated only when read.

  # Examples
  :::{.example}
  ## `default.nix` usage example

  ```nix
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    flake-compatish = builtins.fetchTree lock.nodes.flake-compatish.locked;
  in
  import flake-compatish {
    source = ./.;
    overrides = {
      self = ./.;
      # Not `~/Code/nixpkgs`: pure evaluation rejects `~` while parsing.
      nixpkgs = /. + builtins.getEnv "HOME" + "/Code/nixpkgs";
    };
  }
  ```

  :::
*/
args:
let
  evaluated = import ./nix/core.nix args;
in
evaluated.compat // { compatish = import ./nix/overridable.nix evaluated; }
