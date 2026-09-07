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
#       nixpkgs = "github:nixos/nixpkgs/master";     # string: parsed as flake ref
#     };
#   }
#
#   # With reroot - use an already-evaluated flake for an input, at any depth
#   import flake-compatish {
#     source = ./.;
#     reroot = { nanopynix = <an evaluated flake>; };
#   }
#
# Set FLAKE_COMPATISH_DISABLE_OVERRIDES=1 in the environment to ignore every
# override and evaluate straight from the lockfile.

# Accept both old style (just path) and new style (attrset with source/overrides)
args:

let
  # Normalize arguments: support both `flake-compatish ./.` and `flake-compatish { source = ./.; }`
  normalizedArgs =
    if builtins.isAttrs args then
      args
    else
      {
        source = args;
        overrides = {
          self = args;
        };
      };

  source =
    let
      srcArg = normalizedArgs.source;
    in
    if builtins.isString srcArg then
      fcFetchTree (fcParseFlakeRef srcArg)
    else if builtins.pathExists srcArg then
      srcArg
    else
      throw "source must be a path that exists or a flakeRef";

  suppliedOverrides = normalizedArgs.overrides or { };

  # Flakes to use in place of what the lockfile says, keyed by the name the
  # declaring flake gives the input.
  #
  # `overrides` replaces a node's *source* and keeps the lockfile's idea of
  # that node's own inputs. That is enough one level down and not enough
  # below it: a lockfile can hold a second node for the same dependency, so
  # `nanopynix` reached from `easykubenix` takes `flake-compatish_2`, and no
  # override reaches a name with a suffix.
  #
  # `reroot` replaces the whole flake instead. The caller evaluates each one
  # itself, with whatever inputs it wants, and hands the result in here. So a
  # caller that owns a set of related flakes can make every edge between them
  # point at its own copy, at any depth, without writing `follows` anywhere.
  #
  # The key is the input name and not the node name, which is what makes it
  # reach `flake-compatish_2`: the node has a suffix, the input that names it
  # does not.
  #
  # An input declared `flake = false` is left alone. It is a source and not a
  # flake, and the declaring expression reads it as a path.
  #
  # FLAKE_COMPATISH_DISABLE_OVERRIDES turns this off with the rest, because
  # it means "read the lockfile and nothing else".
  reroot = if overridesDisabled then { } else normalizedArgs.reroot or { };
  nixpkgsArgs = normalizedArgs.nixpkgsArgs or null;
  warnOverrides = normalizedArgs.warnOverrides or true;

  sourceString = toString source;
  lockFilePath = sourceString + "/flake.lock";
  overridesFile = normalizedArgs.overridesFile or (sourceString + "/overrides.nix");

  ###########################################################################
  # Helpers
  ###########################################################################

  # Wrapper for builtins.fetchTree with better error message
  fcFetchTree =
    info:
    let
      ft =
        if builtins.hasAttr "fetchTree" builtins then
          builtins.getAttr "fetchTree" builtins
        else
          throw "flake-compatish requires builtins.fetchTree (Nix 2.4+) with flakes enabled";
    in
    ft info;

  fcParseFlakeRef =
    info:
    let
      prf =
        if builtins.hasAttr "parseFlakeRef" builtins then
          builtins.getAttr "parseFlakeRef" builtins
        else
          throw "flake-compatish requires builtins.parseFlakeRef (Nix 2.4+) with flakes enabled";
    in
    prf info;

  # Create a fake sourceInfo for paths we don't want to copy to store
  mkSourceInfo = path: {
    lastModified = 0;
    lastModifiedDate = "19700101000000";
    outPath = toString path;
  };

  # Resolve an override value to sourceInfo, or null if invalid.
  # - path: use directly without store copy (fast local development)
  # - string: parse as flake reference and fetch (e.g., "github:owner/repo")
  #
  # `tryEval` does not make a missing file safe to import, so callers must
  # guard imports with `pathExists` first.  This check only forces the
  # candidate selected by its declared input name.
  resolveOverride =
    name: override:
    let
      forcedOverride = builtins.tryEval override;
      pathIsUsable =
        if forcedOverride.success then
          builtins.tryEval (builtins.isPath forcedOverride.value && builtins.pathExists forcedOverride.value)
        else
          {
            success = false;
            value = false;
          };
    in
    if pathIsUsable.success && pathIsUsable.value then
      mkSourceInfo forcedOverride.value
    else if forcedOverride.success && builtins.isString forcedOverride.value then
      fcFetchTree (fcParseFlakeRef forcedOverride.value)
    else
      null;

  # `pathExists` must run before `import`; wrapping an import in `tryEval` does
  # not reliably turn a missing-file error into a value.  The extra `tryEval`
  # converts ordinary evaluation failures from a configurable path expression
  # into an absent optional file.
  optionalOverridesFileExists =
    path:
    let
      checked = builtins.tryEval (builtins.pathExists path);
    in
    checked.success && checked.value;

  ###########################################################################
  # Lockfile parsing
  ###########################################################################

  lockFile = builtins.fromJSON (builtins.readFile lockFilePath);

  # A master can provide the arguments for a configured nixpkgs import. The
  # resulting package sets are created once per system from the root nixpkgs
  # node, then reused as compatible flakes' self.legacyPackages entries.
  masterNixpkgsNode =
    if nixpkgsArgs == null then
      null
    else if !(builtins.pathExists lockFilePath) then
      throw "nixpkgsArgs requires a flake.lock with a root nixpkgs input"
    else if !(lockFile.nodes.${lockFile.root}.inputs ? nixpkgs) then
      throw "nixpkgsArgs requires a root nixpkgs input"
    else
      resolveInputSpec lockFile.nodes.${lockFile.root}.inputs.nixpkgs;

  # An escape hatch for reproducing a plain flake evaluation without editing
  # the consumer's expressions: every override is ignored and each node comes
  # from the lockfile.  `getEnv` is empty in pure evaluation, where overrides
  # would already be lockfile-faithful anyway.
  disableOverridesEnv = builtins.getEnv "FLAKE_COMPATISH_DISABLE_OVERRIDES";
  overridesDisabled = disableOverridesEnv != "" && disableOverridesEnv != "0";

  # This file belongs to the consumer and is normally gitignored.  By default
  # it is looked up relative to `source`, never relative to flake-compatish;
  # callers can select a different file with `overridesFile`.  `getEnv` is
  # empty in pure Nix evaluation, so the local file is never imported there
  # even when a dirty flake source happened to copy it into the store.
  isImpureEvaluation = builtins.getEnv "HOME" != "" || builtins.getEnv "USER" != "";
  localOverrides =
    if !overridesDisabled && isImpureEvaluation && optionalOverridesFileExists overridesFile then
      import overridesFile
    else
      { };

  # Do not select an override value until its name is known to be valid. This
  # ignores typoed names and preserves laziness for arbitrary extra attrs.
  rootInputNames = builtins.attrNames (lockFile.nodes.${lockFile.root}.inputs or { });
  isDeclaredOverrideName = name: name == "self" || builtins.elem name rootInputNames;
  getOverride =
    overrides: name:
    if isDeclaredOverrideName name && builtins.hasAttr name overrides then overrides.${name} else null;

  # A local value wins when valid. If it cannot be used (for example because a
  # development path is unavailable in pure evaluation), try the explicit
  # override before falling back to the lockfile.
  warnAppliedOverride =
    name: sourceInfo:
    if warnOverrides then
      builtins.warn "flake-compatish: ${sourceString}: overriding ${name} to ${sourceInfo.outPath}" sourceInfo
    else
      sourceInfo;

  resolveNamedOverride =
    name:
    let
      localOverride = getOverride localOverrides name;
      resolvedLocal = if localOverride != null then resolveOverride name localOverride else null;
      suppliedOverride = getOverride suppliedOverrides name;
    in
    if overridesDisabled then
      null
    else if resolvedLocal != null then
      warnAppliedOverride name resolvedLocal
    else if suppliedOverride != null then
      let
        resolvedSupplied = resolveOverride name suppliedOverride;
      in
      if resolvedSupplied != null then warnAppliedOverride name resolvedSupplied else null
    else
      null;

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

  # The sourceInfo of a node. A flake node carries it as an attribute; a node
  # declared `flake = false` is one already.
  nodeSourceInfo =
    nodeName:
    let
      evaluated = evaluatedNodes.${nodeName};
    in
    evaluated.sourceInfo or evaluated;

  # A `path:` input can be written relative to the flake that declares it,
  # and the lockfile keeps it that way. `parent` records the chain of input
  # names from the root to that flake, and an empty chain means the root
  # itself. fetchTree refuses a relative path, so resolve it here.
  isRelativePath =
    locked: (locked.type or "") == "path" && builtins.substring 0 1 (locked.path or "/") != "/";

  # Where a node's source lies before anything is copied.
  #
  # It has to be the original directory and not the store copy. `../simple`
  # written next to `with-dep` means the sibling of the checkout, and the
  # sibling of a store copy of that checkout is nothing.
  #
  # So a relative path composes onto its parent's original directory, and the
  # chain ends at the root, whose directory is the source this was called
  # with. A parent is always closer to the root, so this terminates.
  #
  # An override of the parent does not move the child. The chain follows the
  # lockfile, so `../simple` under an overridden `with-dep` still means the
  # sibling of the `with-dep` the lockfile named. That is what the lockfile
  # says, and it is the same answer the flake evaluator gives.
  originalDir =
    nodeName:
    if nodeName == lockFile.root then
      sourceString
    else
      let
        node = lockFile.nodes.${nodeName};
      in
      if isRelativePath node.locked then
        originalDir (followPath lockFile.root (node.parent or [ ])) + "/" + node.locked.path
      else
        (nodeSourceInfo nodeName).outPath;

  lockedOf =
    nodeName: node:
    if isRelativePath node.locked then node.locked // { path = originalDir nodeName; } else node.locked;

  # Evaluate all nodes in the lockfile into flake outputs.
  # This is a lazy attrset - nodes are only evaluated when accessed.
  evaluatedNodes = builtins.mapAttrs evaluateNode lockFile.nodes;

  masterNixpkgs = if masterNixpkgsNode != null then evaluatedNodes.${masterNixpkgsNode} else null;

  configuredLegacyPackages =
    if masterNixpkgs != null then
      builtins.mapAttrs (
        system: _: import masterNixpkgs.outPath (nixpkgsArgs system)
      ) masterNixpkgs.legacyPackages
    else
      null;

  # Evaluate a single lockfile node into its flake outputs
  evaluateNode =
    nodeName: node:
    let
      isRootNode = nodeName == lockFile.root;

      # Check for user-provided override (use "self" key for root node)
      overrideKey = if isRootNode then "self" else nodeName;
      # Resolve override (returns null if path doesn't exist)
      resolvedOverride = resolveNamedOverride overrideKey;

      # Fetch or construct the source for this node
      sourceInfo =
        if resolvedOverride != null then
          resolvedOverride
        else if isRootNode then
          # Root node: fetch from source path
          fcFetchTree {
            type = "path";
            path = sourceString;
          }
        else
          # Dependency: fetch using lockfile info
          fcFetchTree (node.info or { } // removeAttrs (lockedOf nodeName node) [ "dir" ]);

      # Handle flakes in subdirectories (e.g., "dir" attribute in lockfile)
      subdir = if isRootNode then "" else node.locked.dir or "";
      flakePath = if subdir == "" then sourceInfo.outPath else "${sourceInfo.outPath}/${subdir}";

      # Import and evaluate the flake
      flake = import (flakePath + "/flake.nix");

      # Recursively resolve this node's inputs to evaluated flakes
      resolvedInputs = builtins.mapAttrs (
        inputName: inputSpec:
        let
          target = resolveInputSpec inputSpec;
        in
        if (lockFile.nodes.${target}.flake or true) && reroot ? ${inputName} then
          reroot.${inputName}
        else
          evaluatedNodes.${target}
      ) (node.inputs or { });

      # Call flake.outputs with resolved inputs + self reference
      flakeOutputs = flake.outputs (resolvedInputs // { self = flakeResult; });

      injectedLegacyPackages =
        if masterNixpkgsNode != null && nodeName != masterNixpkgsNode && flakeOutputs ? legacyPackages then
          builtins.mapAttrs (
            system: original:
            if builtins.hasAttr system configuredLegacyPackages then
              configuredLegacyPackages.${system}
            else
              original
          ) flakeOutputs.legacyPackages
        else
          null;

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
        }
        // (if injectedLegacyPackages != null then { legacyPackages = injectedLegacyPackages; } else { });

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
      resolved = resolveNamedOverride "self";
    in
    if resolved != null then
      resolved.outPath
    else
      (fcFetchTree {
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
