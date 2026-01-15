# A Nix flakes-like implementation in Nix, assumes a modern Nix version with
# fetchTree support. By default copies source into store for flake compatibility.
# Use overrides = { self = ./.; } to use source path directly without store copy.
#
# Usage in default.nix:
#   let
#     lock = builtins.fromJSON (builtins.readFile ./flake.lock);
#     flake-compatish = builtins.fetchTree lock.nodes.flake-compatish.locked;
#   in
#   import flake-compatish ./. # or: { source = ./.; overrides.self = ./.; }

{
  source,
  overrides ? { },
}:
let
  sourceString = builtins.toString source;
  lockFilePath = sourceString + "/flake.lock";

  lockFile = builtins.fromJSON (builtins.readFile lockFilePath);

  fetchTree =
    info:
    let
      ft = builtins.fetchTree or (x: builtins.throw "flake-compatish requires builtins.fetchTree");
    in
    ft info;

  callLocklessFlake =
    flakeSrc:
    let
      flake = import (flakeSrc + "/flake.nix");
      sourceInfo = {
        lastModified = 0;
        lastModifiedDate = 0;
        outPath = flakeSrc;
      };
      outputs = sourceInfo // (flake.outputs { self = outputs; });
    in
    outputs;

  allNodes = builtins.mapAttrs (
    key: node:
    let
      # Check if there's an override (use "self" for root node, otherwise node name)
      override =
        if key == lockFile.root then overrides.self or null
        else overrides.${key} or null;

      sourceInfo =
        if override != null then
          # Use override path directly, bypassing lockfile/fetchTree
          {
            lastModified = 0;
            lastModifiedDate = 0;
            outPath = builtins.toString override;
          }
        else if key == lockFile.root then
          fetchTree { type = "path"; path = sourceString; }
        else
          fetchTree (node.info or { } // removeAttrs node.locked [ "dir" ]);

      subdir = if key == lockFile.root then "" else node.locked.dir or "";

      outPath = sourceInfo + ((if subdir == "" then "" else "/") + subdir);

      flake = import (outPath + "/flake.nix");

      inputs = builtins.mapAttrs (inputName: inputSpec: allNodes.${resolveInput inputSpec}) (
        node.inputs or { }
      );

      # Resolve a input spec into a node name. An input spec is
      # either a node name, or a 'follows' path from the root
      # node.
      resolveInput =
        inputSpec: if builtins.isList inputSpec then getInputByPath lockFile.root inputSpec else inputSpec;

      # Follow an input path (e.g. ["dwarffs" "nixpkgs"]) from the
      # root node, returning the final node.
      getInputByPath =
        nodeName: path:
        if path == [ ] then
          nodeName
        else
          getInputByPath
            # Since this could be a 'follows' input, call resolveInput.
            (resolveInput lockFile.nodes.${nodeName}.inputs.${builtins.head path})
            (builtins.tail path);

      outputs = flake.outputs (inputs // { self = result; });

      result =
        outputs
        # We add the sourceInfo attribute for its metadata, as they are
        # relevant metadata for the flake. However, the outPath of the
        # sourceInfo does not necessarily match the outPath of the flake,
        # as the flake may be in a subdirectory of a source.
        # This is shadowed in the next //
        // sourceInfo
        // {
          # This shadows the sourceInfo.outPath
          inherit outPath;

          inherit inputs;
          inherit outputs;
          inherit sourceInfo;
          _type = "flake";
        };

    in
    if node.flake or true then
      assert builtins.isFunction flake.outputs;
      result
    else
      sourceInfo
  ) lockFile.nodes;

  rootSrc =
    let override = overrides.self or null;
    in
    if override != null then builtins.toString override
    else (fetchTree { type = "path"; path = sourceString; }).outPath;

  result =
    if !(builtins.pathExists lockFilePath) then
      callLocklessFlake rootSrc
    else if lockFile.version >= 5 && lockFile.version <= 7 then
      allNodes.${lockFile.root}
    else
      throw "lock file '${lockFilePath}' has unsupported version ${toString lockFile.version}";

in
{
  inputs = result.inputs or { } // {
    self = result;
  };

  outputs = result;
  # Try to get rid of redundant system attribute levels, this fails if you have packages named after builtins.currentSystem
  impure = builtins.mapAttrs (n: v: v.${builtins.currentSystem} or v) result;
}
