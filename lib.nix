/**
  The overridable entrypoint. `default.nix` stays a plain flake-compat shim;
  this one returns a result you can override again after import, after
  [sprinkles](https://git.afnix.fr/sprinkles/sprinkles).
*/
let
  core = import ./nix/core.nix;
  overridable = import ./nix/overridable.nix;
in
{
  /**
    Evaluate a flake, and return a result that can be overridden again.

    The result has the attributes `default.nix` returns, and also:

    `args`
    : The arguments this result was evaluated with.

    `sources`
    : The root's inputs as fetched: after `overrides`, before `reroot`.

    `override`
    : Re-evaluate with changed arguments. An attrset merges into `args`,
      and its `overrides` and `reroot` merge key by key. A function gets
      the previous `args` and returns the attrset to merge with `//`, so it
      can also remove a key.

    # Inputs

    `args`
    : A path, or an attrset with the arguments `default.nix` takes. Also:

      `strict` (default `true`)
      : Abort on an `overrides` name that is not `self` or a root input,
        and on a `reroot` name that no flake in the graph declares.
        `default.nix` ignores such names; here they are typos until proved
        otherwise. A local `overrides.nix` is never checked, because it is
        the machine's and not the project's.

    A `reroot` value can be a function. It gets the flake that would have
    been used, and returns the one to use instead.

    # Examples
    :::{.example}
    ## `new` usage example

    ```nix
    let
      fc = import "${flake-compatish}/lib.nix";
      flake = fc.new ./.;
    in
    (flake.override { overrides.nixpkgs = /. + builtins.getEnv "HOME" + "/Code/nixpkgs"; })
      .impure.packages.default
    ```

    :::
  */
  new = args: overridable (core args);
}
