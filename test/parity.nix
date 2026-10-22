# Compares flake-compatish with the flake evaluator, `builtins.getFlake`, on
# the flakes in ./parity. Their lockfiles are what `nix flake lock` writes.
#
# A flake reference as `source` must give exactly what the flake evaluator
# gives, at every depth. `deviations` asserts each documented difference,
# so a change that removes one fails too. The README lists them, with the
# reasons.
#
# Run with: nix eval --impure --file ./test/parity.nix
# The fixtures must be committed: the flake evaluator reads the git tree. A
# clean shallow clone fails under both evaluators: no revCount.
let
  flake-compatish = import ../.;
  repo = toString ../.;
  gitRef = name: "git+file://${repo}?dir=test/parity/${name}";
  pathRef = name: "path:${repo}/test/parity/${name}";

  summarize =
    flake:
    if flake ? _type then
      {
        attrs = builtins.attrNames flake;
        inherit (flake) _type outPath sourceInfo outputs;
        inputs = builtins.mapAttrs (_: summarize) flake.inputs;
      }
    else
      flake;

  /**
    The places where `real` and `compat` differ, as a list of
    `{ path; real; compat; }`. Attrsets are compared key by key.
  */
  diff =
    path: real: compat:
    if builtins.isAttrs real && builtins.isAttrs compat then
      builtins.concatMap (
        name: diff (path ++ [ name ]) (real.${name} or "<missing>") (compat.${name} or "<missing>")
      ) (builtins.attrNames (real // compat))
    else if real == compat then
      [ ]
    else
      [
        {
          path = builtins.concatStringsSep "." path;
          inherit real compat;
        }
      ];

  compare = compareWith summarize;

  # nixpkgs has no flake.lock. Its outputs are too large to compare whole;
  # a package's drvPath and `lib.version` stand for them.
  nixpkgs = toString <nixpkgs>;
  summarizeNixpkgs = flake: {
    attrs = builtins.attrNames flake;
    inherit (flake) _type outPath sourceInfo;
    inputs = builtins.attrNames flake.inputs;
    outputs = builtins.attrNames flake.outputs;
    version = flake.lib.version;
    hello = flake.legacyPackages.${builtins.currentSystem}.hello.drvPath;
  };
  compareNixpkgs = compareWith summarizeNixpkgs;

  /**
    Compare under `summary`. The flake evaluator goes first: after a
    `fetchTree` of the same path in the same evaluation, `getFlake` gives a
    sourceInfo with `outPath` alone (Nix 2.35).
  */
  compareWith =
    summary: ref:
    let
      real = builtins.getFlake ref;
    in
    builtins.seq (builtins.attrNames real.sourceInfo) (
      diff [ ] (summary real) (summary (flake-compatish { source = ref; }).outputs)
    );

  comparisons = {
    nixpkgs = compareNixpkgs "path:${nixpkgs}";
    leaf = compare (gitRef "leaf");
    mid = compare (gitRef "mid");
    top = compare (gitRef "top");
    # A `path:` flake with no relative inputs: both copy the directory alone.
    leafPath = compare (pathRef "leaf");
  };

  inPlace = (flake-compatish (/. + "${repo}/test/parity/top")).outputs;
  copied = (flake-compatish { source = /. + "${repo}/test/parity/top"; }).outputs;

  nixpkgsInPlace = (flake-compatish (/. + nixpkgs)).outputs;

  deviations = {
    # nixpkgs in place: the same package set, with the in-place sourceInfo.
    nixpkgsInPlace =
      nixpkgsInPlace.legacyPackages.${builtins.currentSystem}.hello.drvPath
      == (builtins.getFlake "path:${nixpkgs}").legacyPackages.${builtins.currentSystem}.hello.drvPath
      && builtins.attrNames nixpkgsInPlace.sourceInfo == [
        "lastModified"
        "lastModifiedDate"
        "outPath"
      ];
    # A path is used in place: no store copy, so no narHash, and no time.
    # outPath is a path value, not a string, so a build that uses it gets a
    # store copy.
    inPlaceSourceInfo = inPlace.sourceInfo == {
      lastModified = 0;
      lastModifiedDate = "19700101000000";
      outPath = /. + "${repo}/test/parity/top";
    };
    # Its relative inputs are in place too, as paths under the checkout.
    inPlaceRelative =
      builtins.isPath inPlace.leafOutPath && toString inPlace.leafOutPath == "${repo}/test/parity/leaf";
    # A copied path reaches its siblings from the original directory, and
    # copies each one. The flake evaluator cannot reach them.
    copiedReachesSiblings =
      copied.nestedValue == "nested"
      && builtins.substring 0 11 copied.leafOutPath == "/nix/store/"
      && copied.inputs.mid.sourceInfo != copied.sourceInfo;
  };

  differing = builtins.filter (name: comparisons.${name} != [ ]) (builtins.attrNames comparisons);
  broken = builtins.filter (name: !deviations.${name}) (builtins.attrNames deviations);
in
if differing != [ ] then
  throw "FAILED: flake-compatish differs from the flake evaluator: ${
    builtins.toJSON (builtins.intersectAttrs (builtins.listToAttrs (map (n: { name = n; value = null; }) differing)) comparisons)
  }"
else if broken != [ ] then
  throw "FAILED: documented deviations changed: ${builtins.concatStringsSep ", " broken}"
else
  "All ${toString (builtins.length (builtins.attrNames comparisons))} parity comparisons and ${
    toString (builtins.length (builtins.attrNames deviations))
  } deviation checks passed!"
