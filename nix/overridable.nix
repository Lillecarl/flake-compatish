/**
  Wraps one core evaluation into the overridable result that `lib.nix`
  documents. Internal.

  It takes the core's output, not its arguments, so `default.nix` can share
  a single evaluation between its own attributes and `compatish`.

  # Type

  ```
  overridable :: CoreResult -> AttrSet
  ```
*/
let
  core = import ./core.nix;

  /**
    Merge an override attrset into arguments. `overrides` and `reroot` merge
    key by key; every other key replaces.

    # Type

    ```
    mergeArgs :: AttrSet -> AttrSet -> AttrSet
    ```
  */
  mergeArgs =
    prev: update:
    prev
    // update
    // {
      overrides = prev.overrides or { } // update.overrides or { };
      reroot = prev.reroot or { } // update.reroot or { };
    };

  /**
    The names of `given` that are not in `known`.

    # Type

    ```
    unknownNames :: AttrSet -> [String] -> [String]
    ```
  */
  unknownNames =
    given: known: builtins.filter (name: !(builtins.elem name known)) (builtins.attrNames given);

  quoteNames = names: builtins.concatStringsSep ", " (map (name: "`${name}`") names);

  overridable =
    evaluated:
    let
      strict = evaluated.args.strict or true;
      badOverrides = unknownNames (evaluated.args.overrides or { }) evaluated.overrideNames;
      badReroots = unknownNames (evaluated.args.reroot or { }) evaluated.rerootNames;
      result = evaluated.compat // {
        inherit (evaluated) args sources;
        override =
          update:
          overridable (
            core (
              if builtins.isFunction update then
                evaluated.args // update evaluated.args
              else
                mergeArgs evaluated.args update
            )
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
overridable
