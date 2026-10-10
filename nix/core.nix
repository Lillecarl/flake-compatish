/**
  The evaluator behind both entrypoints. Internal: the public interface is
  `default.nix` and `lib.nix`.

  `default.nix` returns `compat`. `nix/overridable.nix` also reads the
  attributes beside it.

  # Inputs

  `args`
  : A path, or the attrset `default.nix` documents.
*/
args:

let
  # `import flake-compatish ./.` means "this directory, in place".
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
  # A value can also be a function. It gets the flake the lockfile (and
  # `overrides`) would have supplied, and returns the one to use. Flakes are
  # attrsets, so `isFunction` tells the two forms apart.
  #
  # FLAKE_COMPATISH_DISABLE_OVERRIDES turns this off with the rest, because
  # it means "read the lockfile and nothing else".
  reroot = if overridesDisabled then { } else normalizedArgs.reroot or { };

  # Keyed by input name, then by target node. The function form is called
  # once per pair and not once per edge: Nix memoizes attrset values and not
  # function calls, and a function that imports nixpkgs is expensive.
  rerootedNodes = builtins.mapAttrs (
    inputName: value:
    if builtins.isFunction value then
      builtins.mapAttrs (target: _: value evaluatedNodes.${target}) lockFile.nodes
    else
      null
  ) reroot;

  /**
    The flake `reroot` gives for an input name that points at a node.

    # Inputs

    `inputName`
    : A key of `reroot`.

    `target`
    : The lockfile node the input would have resolved to.

    # Type

    ```
    rerootFor :: String -> String -> AttrSet
    ```
  */
  rerootFor =
    inputName: target:
    let
      value = reroot.${inputName};
    in
    if builtins.isFunction value then rerootedNodes.${inputName}.${target} else value;

  nixpkgsArgs = normalizedArgs.nixpkgsArgs or null;
  warnOverrides = normalizedArgs.warnOverrides or true;

  sourceString = toString source;
  lockFilePath = sourceString + "/flake.lock";
  overridesFile = normalizedArgs.overridesFile or (sourceString + "/overrides.nix");

  ###########################################################################
  # Helpers
  ###########################################################################

  /**
    `builtins.fetchTree`, with an error that names the requirement when the
    builtin is missing.

    # Type

    ```
    fcFetchTree :: AttrSet -> AttrSet
    ```
  */
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

  /**
    `builtins.parseFlakeRef`, with an error that names the requirement when
    the builtin is missing.

    # Type

    ```
    fcParseFlakeRef :: String -> AttrSet
    ```
  */
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

  /**
    A sourceInfo for a path used in place, without a store copy.

    # Type

    ```
    mkSourceInfo :: Path -> AttrSet
    ```
  */
  mkSourceInfo = path: {
    lastModified = 0;
    lastModifiedDate = "19700101000000";
    outPath = toString path;
  };

  /**
    The sourceInfo for one override value, or `null` when it cannot be used.

    A path that exists is used in place. A string is a flake reference and is
    fetched. Anything else, and a value that fails to evaluate, gives `null`.

    `tryEval` does not make a missing file safe to import, so callers must
    guard imports with `pathExists` first. This check only forces the
    candidate selected by its declared input name.

    # Inputs

    `name`
    : The input name, for the caller's warning.

    `override`
    : The value from `overrides` or the local file.

    # Type

    ```
    resolveOverride :: String -> (Path | String) -> AttrSet | Null
    ```
  */
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

  /**
    Whether the optional local override file can be imported.

    `pathExists` must run before `import`; wrapping an import in `tryEval`
    does not reliably turn a missing-file error into a value. The extra
    `tryEval` converts ordinary evaluation failures from a configurable path
    expression into an absent optional file.

    # Type

    ```
    optionalOverridesFileExists :: Path -> Bool
    ```
  */
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

  # Pure evaluation removes `currentSystem` from `builtins`. Not a `getEnv`
  # test: an impure evaluation with an empty environment, such as `env -i`
  # or a systemd unit, has no HOME or USER either.
  #
  # The override files are gated by this and not wrapped in `tryEval`: pure
  # mode rejects `~` while parsing, and `tryEval` around the `import` does
  # not catch that (Nix 2.35). Skipping the import is the only safe form.
  isImpureEvaluation = builtins ? currentSystem;

  # This file belongs to the consumer and is normally gitignored.  By default
  # it is looked up relative to `source`, never relative to flake-compatish;
  # callers can select a different file with `overridesFile`.  It is never
  # imported in pure evaluation, even when a dirty flake source happened to
  # copy it into the store.
  localOverrides =
    if !overridesDisabled && isImpureEvaluation && optionalOverridesFileExists overridesFile then
      import overridesFile
    else
      { };

  # The machine's overrides for every flake-compatish evaluation, matched by
  # flake reference rather than by input name: one repository's `nixpkgs` can
  # be another's 24.05 pin, so a name means nothing across repositories.
  #
  # Found through the NIX_PATH entry `flake-compatish-overrides`, read from
  # `builtins.nixPath` and not through `<...>`. Pure evaluation has an empty
  # `nixPath`, and the `isImpureEvaluation` gate covers an explicit value.
  systemOverridesArg = normalizedArgs.systemOverrides or true;
  systemOverridesEntries = builtins.filter (
    entry: entry.prefix == "flake-compatish-overrides"
  ) builtins.nixPath;
  systemOverridesSource =
    if systemOverridesArg == true then
      (if systemOverridesEntries == [ ] then null else (builtins.head systemOverridesEntries).path)
    else if systemOverridesArg == false then
      null
    else
      systemOverridesArg;
  systemOverrides =
    if overridesDisabled || !isImpureEvaluation || systemOverridesSource == null then
      null
    else if builtins.isPath systemOverridesSource || builtins.isString systemOverridesSource then
      (if optionalOverridesFileExists systemOverridesSource then import systemOverridesSource else null)
    else
      systemOverridesSource;

  upperCase = builtins.genList (i: builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZ") 26;
  lowerCase = builtins.genList (i: builtins.substring i 1 "abcdefghijklmnopqrstuvwxyz") 26;

  /**
    A flake reference attrset with `owner` and `repo` in lower case, because
    GitHub, GitLab and SourceHut compare them that way, and a lockfile keeps
    whatever case the flake author wrote.

    # Type

    ```
    normalizeRef :: AttrSet -> AttrSet
    ```
  */
  normalizeRef =
    ref:
    builtins.mapAttrs (
      name: value:
      if name == "owner" || name == "repo" then
        builtins.replaceStrings upperCase lowerCase value
      else
        value
    ) ref;

  # Parsed once, not once per node.
  systemOverrideKeys =
    if builtins.isAttrs systemOverrides then
      map (key: {
        inherit key;
        ref = normalizeRef (fcParseFlakeRef key);
      }) (builtins.attrNames systemOverrides)
    else
      [ ];

  /**
    Whether every attribute of `key` is in `target` with the same value. So
    `github:NixOS/nixpkgs` matches any branch, and
    `github:NixOS/nixpkgs/nixos-unstable` only that one.

    # Type

    ```
    refMatches :: AttrSet -> AttrSet -> Bool
    ```
  */
  refMatches =
    key: target:
    builtins.all (name: target ? ${name} && target.${name} == key.${name}) (builtins.attrNames key);

  /**
    The system-wide override value for a lockfile node, or `null`.

    A key matches the node's `original` or its `locked` reference. `locked`
    is what lets `github:NixOS/nixpkgs` match an input written as the
    registry name `nixpkgs`. When several keys match, the one with the most
    attributes wins.

    A function as the whole file gets `{ nodeName, original, locked }` and
    returns the value or `null`.

    # Type

    ```
    systemOverrideFor :: String -> AttrSet -> Any | Null
    ```
  */
  systemOverrideFor =
    nodeName: node:
    if systemOverrides == null then
      null
    else if builtins.isFunction systemOverrides then
      systemOverrides {
        inherit nodeName;
        original = node.original or { };
        locked = node.locked or { };
      }
    else
      let
        targets = map normalizeRef (
          builtins.filter (ref: ref != null) [
            (node.original or null)
            (node.locked or null)
          ]
        );
        matching = builtins.filter (
          candidate: builtins.any (refMatches candidate.ref) targets
        ) systemOverrideKeys;
        best = builtins.foldl' (
          acc: candidate:
          if
            acc == null
            || builtins.length (builtins.attrNames candidate.ref) > builtins.length (builtins.attrNames acc.ref)
          then
            candidate
          else
            acc
        ) null matching;
      in
      if best == null then null else systemOverrides.${best.key};

  # Do not select an override value until its name is known to be valid. This
  # ignores typoed names and preserves laziness for arbitrary extra attrs.
  rootInputNames = builtins.attrNames (lockFile.nodes.${lockFile.root}.inputs or { });
  isDeclaredOverrideName = name: name == "self" || builtins.elem name rootInputNames;

  /**
    The value `overrides` gives for a name, or `null`. The value is not
    forced.

    # Type

    ```
    getOverride :: AttrSet -> String -> Any | Null
    ```
  */
  getOverride =
    overrides: name:
    if isDeclaredOverrideName name && builtins.hasAttr name overrides then overrides.${name} else null;

  /**
    Return `sourceInfo`, with a warning first when `warnOverrides` is set.

    `origin` is appended to the message, so it names where a system-wide
    override came from.

    # Type

    ```
    warnAppliedOverride :: String -> String -> AttrSet -> AttrSet
    ```
  */
  warnAppliedOverride =
    name: origin: sourceInfo:
    if warnOverrides then
      builtins.warn "flake-compatish: ${sourceString}: overriding ${name} to ${sourceInfo.outPath}${origin}" sourceInfo
    else
      sourceInfo;

  /**
    The sourceInfo that overrides give for a lockfile node, or `null` to use
    the lockfile.

    The first value that can be used wins: the local file by name, then the
    system-wide overrides by reference, then `overrides` by name. A value
    that cannot be used, for example a development path that is unavailable
    here, passes to the next. Each candidate is forced only when every one
    before it has failed.

    # Inputs

    `name`
    : The node name, or `self` for the root.

    `node`
    : The lockfile node, or `null` for the root, which no system-wide
      override reaches.

    # Type

    ```
    resolveNodeOverride :: String -> AttrSet | Null -> AttrSet | Null
    ```
  */
  resolveNodeOverride =
    name: node:
    let
      candidates = [
        {
          value = getOverride localOverrides name;
          origin = "";
        }
        {
          value = if node == null then null else systemOverrideFor name node;
          origin = " (system-wide)";
        }
        {
          value = getOverride suppliedOverrides name;
          origin = "";
        }
      ];
      resolve =
        candidate:
        let
          sourceInfo = if candidate.value == null then null else resolveOverride name candidate.value;
        in
        if sourceInfo == null then
          null
        else
          {
            inherit sourceInfo;
            inherit (candidate) origin;
          };
      # `foldl'` forces each accumulator, so a candidate is resolved only
      # once all before it gave `null`.
      first = builtins.foldl' (
        acc: candidate: if acc != null then acc else resolve candidate
      ) null candidates;
    in
    if overridesDisabled || first == null then
      null
    else
      warnAppliedOverride name first.origin first.sourceInfo;

  resolveNamedOverride = name: resolveNodeOverride name null;

  /**
    The node name an input spec points at.

    # Inputs

    `inputSpec`
    : A node name such as `"nixpkgs"`, or a `follows` path from the root such
      as `[ "dwarffs" "nixpkgs" ]`.

    # Type

    ```
    resolveInputSpec :: (String | [String]) -> String
    ```
  */
  resolveInputSpec =
    inputSpec: if builtins.isList inputSpec then followPath lockFile.root inputSpec else inputSpec;

  /**
    Walk a `follows` path through the lockfile graph, one input name at a
    time.

    # Type

    ```
    followPath :: String -> [String] -> String
    ```

    # Examples
    :::{.example}
    ## `followPath` usage example

    ```nix
    followPath "root" [ "dwarffs" "nixpkgs" ]
    => "nixpkgs_2"   # the node dwarffs names as its nixpkgs
    ```

    :::
  */
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

  /**
    The sourceInfo of a node. A flake node carries it as an attribute; a node
    declared `flake = false` is one already.

    # Type

    ```
    nodeSourceInfo :: String -> AttrSet
    ```
  */
  nodeSourceInfo =
    nodeName:
    let
      evaluated = evaluatedNodes.${nodeName};
    in
    evaluated.sourceInfo or evaluated;

  /**
    Whether a locked input is a relative `path:`.

    A `path:` input can be written relative to the flake that declares it,
    and the lockfile keeps it that way. `parent` records the chain of input
    names from the root to that flake, and an empty chain means the root
    itself. fetchTree refuses a relative path, so `lockedOf` resolves it.

    # Type

    ```
    isRelativePath :: AttrSet -> Bool
    ```
  */
  isRelativePath =
    locked: (locked.type or "") == "path" && builtins.substring 0 1 (locked.path or "/") != "/";

  /**
    Where a node's source lies before anything is copied.

    It has to be the original directory and not the store copy. `../simple`
    written next to `with-dep` means the sibling of the checkout, and the
    sibling of a store copy of that checkout is nothing.

    So a relative path composes onto its parent's original directory, and the
    chain ends at the root, whose directory is the source this was called
    with. A parent is always closer to the root, so this terminates.

    An override of the parent does not move the child. The chain follows the
    lockfile, so `../simple` under an overridden `with-dep` still means the
    sibling of the `with-dep` the lockfile named. That is what the lockfile
    says, and it is the same answer the flake evaluator gives.

    # Type

    ```
    originalDir :: String -> String
    ```
  */
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

  /**
    A node's `locked` attrset, with a relative path made absolute so that
    fetchTree accepts it.

    # Type

    ```
    lockedOf :: String -> AttrSet -> AttrSet
    ```
  */
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

  /**
    One lockfile node, evaluated: a flake result, or a sourceInfo for a node
    declared `flake = false`.

    # Inputs

    `nodeName`
    : The node's key in `lockFile.nodes`.

    `node`
    : The node itself.

    # Type

    ```
    evaluateNode :: String -> AttrSet -> AttrSet
    ```
  */
  evaluateNode =
    nodeName: node:
    let
      isRootNode = nodeName == lockFile.root;

      resolvedOverride =
        if isRootNode then resolveNamedOverride "self" else resolveNodeOverride nodeName node;

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
          rerootFor inputName target
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

  /**
    A flake with no `flake.lock`, and so no inputs except `self`.

    # Type

    ```
    evaluateLocklessFlake :: Path -> AttrSet
    ```
  */
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

  hasLockFile = builtins.pathExists lockFilePath;

in
{
  /**
    What `default.nix` returns, without `compatish`: `inputs`, `outputs` and
    `impure`.
  */
  compat = {
    # Standard flake-compat interface
    inputs = (rootFlake.inputs or { }) // {
      self = rootFlake;
    };
    outputs = rootFlake;

    # Convenience: auto-select current system from outputs
    # e.g., impure.packages.hello instead of outputs.packages.x86_64-linux.hello
    impure = builtins.mapAttrs (name: value: value.${builtins.currentSystem} or value) rootFlake;
  };

  /**
    The arguments as an attrset. A path argument becomes
    `{ source = path; overrides.self = path; }`.
  */
  args = normalizedArgs;

  /**
    The names `overrides` accepts: `self` and the root's inputs.
  */
  overrideNames = [ "self" ] ++ (if hasLockFile then rootInputNames else [ ]);

  /**
    The names `reroot` accepts: every input name declared anywhere in the
    graph.
  */
  rerootNames =
    if hasLockFile then
      builtins.attrNames (
        builtins.foldl' (acc: node: acc // node.inputs or { }) { } (builtins.attrValues lockFile.nodes)
      )
    else
      [ ];

  /**
    The root's inputs as fetched, after `overrides` and before `reroot`.
  */
  sources =
    if hasLockFile then
      builtins.mapAttrs (
        _: inputSpec: nodeSourceInfo (resolveInputSpec inputSpec)
      ) lockFile.nodes.${lockFile.root}.inputs or { }
    else
      { };
}
