# flake-compatish, the involved entrypoint. `default.nix` stays the plain
# flake-compat shim; this adds what sprinkles has and it lacks.
let
  core = import ./nix/core.nix;

  mergeArgs =
    prev: update:
    prev
    // update
    // {
      overrides = prev.overrides or { } // update.overrides or { };
      reroot = prev.reroot or { } // update.reroot or { };
    };

  unknownNames =
    given: known: builtins.filter (name: !(builtins.elem name known)) (builtins.attrNames given);

  quoteNames = names: builtins.concatStringsSep ", " (map (name: "`${name}`") names);
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
      fc = import flake-compatish/lib.nix;
      flake = fc.new ./.;
    in
    (flake.override { overrides.nixpkgs = ~/Code/nixpkgs; }).impure.packages.default
    ```

    :::
  */
  new =
    let
      new =
        args:
        let
          evaluated = core args;
          strict = evaluated.args.strict or true;
          badOverrides = unknownNames (evaluated.args.overrides or { }) evaluated.overrideNames;
          badReroots = unknownNames (evaluated.args.reroot or { }) evaluated.rerootNames;
          result = evaluated.compat // {
            inherit (evaluated) args sources;
            override =
              update:
              new (
                if builtins.isFunction update then
                  evaluated.args // update evaluated.args
                else
                  mergeArgs evaluated.args update
              );
          };
        in
        if strict && badOverrides != [ ] then
          throw "flake-compatish: no input to override named ${quoteNames badOverrides}; known: ${quoteNames evaluated.overrideNames}"
        else if strict && badReroots != [ ] then
          throw "flake-compatish: no input to reroot named ${quoteNames badReroots}; known: ${quoteNames evaluated.rerootNames}"
        else
          result;
    in
    new;
}
