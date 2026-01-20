# flake-compatish: Evaluate flakes without the flake evaluator
#
# A pure-Nix implementation that reads flake.nix and flake.lock to produce
# flake outputs. Requires builtins.fetchTree (Nix 2.4+).
#
# Usage:
#   # Minimal - copies source to store (flake-compatible purity)
#   import flake-compatish ./.
#
#   # With overrides - use local paths or flake refs
#   import flake-compatish {
#     source = ./.;
#     overrides = {
#       self = ./.;                                  # path: use directly, no store copy
#       nixpkgs = ~/Code/nixpkgs;                    # path: local checkout
#       nixpkgs = "github:nixos/nixpkgs/master";    # string: parsed as flake ref
#     };
#   }

# Accept both old style (just path) and new style (attrset with source/overrides)
args:

let
  # Normalize arguments: support both `flake-compatish ./.` and `flake-compatish { source = ./.; }`
  normalizedArgs =
    if builtins.isAttrs args then args
    else { source = args; };

  source = normalizedArgs.source;
  overrides = normalizedArgs.overrides or { };

  sourceString = builtins.toString source;
  lockFilePath = sourceString + "/flake.lock";

  ###########################################################################
  # Helpers
  ###########################################################################

  # Wrapper for builtins.fetchTree with better error message
  fetchTree =
    info:
    let
      ft =
        builtins.fetchTree
          or (throw "flake-compatish requires builtins.fetchTree (Nix 2.4+) with flakes enabled");
    in
    ft info;

  parseFlakeRef =
    info:
    let
      prf =
        builtins.parseFlakeRef
          or (throw "flake-compatish requires builtins.parseFlakeRef (Nix 2.4+) with flakes enabled");
    in
    prf info;

  # Create a fake sourceInfo for paths we don't want to copy to store
  mkSourceInfo = path: {
    lastModified = 0;
    lastModifiedDate = 0;
    outPath = builtins.toString path;
  };

  # Resolve an override value to sourceInfo, or null if invalid
  # - path: use directly without store copy (fast local development)
  # - string: parse as flake reference and fetch (e.g., "github:owner/repo")
  # Returns null (with warning) if path override doesn't exist
  resolveOverride = name: override:
    if builtins.isString override then
      fetchTree (parseFlakeRef override)
    else if builtins.pathExists override then
      mkSourceInfo override
    else
      builtins.trace
        "flake-compatish: override '${name}' path does not exist: ${toString override}, falling back to lockfile"
        null;

  ###########################################################################
  # Lockfile parsing
  ###########################################################################

  lockFile = builtins.fromJSON (builtins.readFile lockFilePath);

  # Resolve an input spec to a node name.
  # Input specs are either:
  #   - A string: direct reference to a node (e.g., "nixpkgs")
  #   - A list: "follows" path to traverse (e.g., ["dwarffs", "nixpkgs"])
  resolveInputSpec =
    inputSpec: if builtins.isList inputSpec then followPath lockFile.root inputSpec else inputSpec;

  # Follow a "follows" path through the lockfile node graph.
  # Example: followPath "root" ["dwarffs", "nixpkgs"]
  #   1. Look up root's input "dwarffs" -> resolves to node "dwarffs"
  #   2. Look up dwarffs's input "nixpkgs" -> resolves to final node
  followPath =
    nodeName: path:
    if path == [ ] then
      nodeName
    else
      let
        nextInputSpec = lockFile.nodes.${nodeName}.inputs.${builtins.head path};
        nextNodeName = resolveInputSpec nextInputSpec;
      in
      followPath nextNodeName (builtins.tail path);

  ###########################################################################
  # Node evaluation
  ###########################################################################

  # Evaluate all nodes in the lockfile into flake outputs.
  # This is a lazy attrset - nodes are only evaluated when accessed.
  evaluatedNodes = builtins.mapAttrs evaluateNode lockFile.nodes;

  # Evaluate a single lockfile node into its flake outputs
  evaluateNode =
    nodeName: node:
    let
      isRootNode = nodeName == lockFile.root;

      # Check for user-provided override (use "self" key for root node)
      overrideKey = if isRootNode then "self" else nodeName;
      override = overrides.${overrideKey} or null;

      # Resolve override (returns null if path doesn't exist)
      resolvedOverride = if override != null then resolveOverride overrideKey override else null;

      # Fetch or construct the source for this node
      sourceInfo =
        if resolvedOverride != null then
          resolvedOverride
        else if isRootNode then
          # Root node: fetch from source path
          fetchTree {
            type = "path";
            path = sourceString;
          }
        else
          # Dependency: fetch using lockfile info
          fetchTree (node.info or { } // removeAttrs node.locked [ "dir" ]);

      # Handle flakes in subdirectories (e.g., "dir" attribute in lockfile)
      subdir = if isRootNode then "" else node.locked.dir or "";
      flakePath = if subdir == "" then sourceInfo.outPath else "${sourceInfo.outPath}/${subdir}";

      # Import and evaluate the flake
      flake = import (flakePath + "/flake.nix");

      # Recursively resolve this node's inputs to evaluated flakes
      resolvedInputs = builtins.mapAttrs (
        inputName: inputSpec: evaluatedNodes.${resolveInputSpec inputSpec}
      ) (node.inputs or { });

      # Call flake.outputs with resolved inputs + self reference
      flakeOutputs = flake.outputs (resolvedInputs // { self = flakeResult; });

      # Construct the final flake result with standard attributes
      flakeResult =
        flakeOutputs
        // sourceInfo
        // {
          outPath = flakePath; # May differ from sourceInfo.outPath if subdir
          inputs = resolvedInputs;
          outputs = flakeOutputs;
          inherit sourceInfo;
          _type = "flake";
        };

    in
    # node.flake defaults to true; if false, this is a non-flake source
    if node.flake or true then
      assert builtins.isFunction flake.outputs;
      flakeResult
    else
      sourceInfo;

  ###########################################################################
  # Lockless flake support
  ###########################################################################

  # For flakes without a lockfile (no dependencies)
  evaluateLocklessFlake =
    flakeSrc:
    let
      flake = import (flakeSrc + "/flake.nix");
      sourceInfo = mkSourceInfo flakeSrc;
      flakeOutputs = flake.outputs { self = flakeResult; };
      flakeResult = flakeOutputs // sourceInfo;
    in
    flakeResult;

  # Determine root source path (respects overrides.self)
  rootSourcePath =
    let
      override = overrides.self or null;
      resolved = if override != null then resolveOverride "self" override else null;
    in
    if resolved != null then
      resolved.outPath
    else
      (fetchTree {
        type = "path";
        path = sourceString;
      }).outPath;

  ###########################################################################
  # Main entry point
  ###########################################################################

  rootFlake =
    if !(builtins.pathExists lockFilePath) then
      evaluateLocklessFlake rootSourcePath
    else if lockFile.version >= 5 && lockFile.version <= 7 then
      evaluatedNodes.${lockFile.root}
    else
      throw "Unsupported flake.lock version ${toString lockFile.version} (supported: 5-7)";

in
{
  # Standard flake-compat interface
  inputs = (rootFlake.inputs or { }) // {
    self = rootFlake;
  };
  outputs = rootFlake;

  # Convenience: auto-select current system from outputs
  # e.g., impure.packages.hello instead of outputs.packages.x86_64-linux.hello
  impure = builtins.mapAttrs (name: value: value.${builtins.currentSystem} or value) rootFlake;
}
