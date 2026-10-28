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

  srcArg = normalizedArgs.source;
  srcLocal = localTree srcArg;
  sourceRef = if srcLocal == null then fcParseFlakeRef srcArg else null;

  # A flake reference is fetched once, and its sourceInfo is the root's, as
  # with the flake evaluator. fetchTree does not take `dir`; the flake is in
  # that subdirectory of the tree.
  # fetchTree fetches git shallow unless told not to, and gives no
  # `revCount` then; the flake evaluator gives one (Nix 2.35).
  sourceTree =
    if sourceRef == null then
      null
    else
      fcFetchTree (
        (if sourceRef.type == "git" then { shallow = false; } else { }) // removeAttrs sourceRef [ "dir" ]
      );
  sourceDir =
    if sourceRef != null then
      sourceRef.dir or ""
    else if rootInPlace then
      srcLocal.subdir
    else
      "";

  source =
    if sourceTree != null then
      (if sourceDir == "" then sourceTree.outPath else "${sourceTree.outPath}/${sourceDir}")
    else if builtins.pathExists srcLocal.dir then
      srcLocal.dir
    else
      throw "source must be a path that exists or a flakeRef";

  # A local source is read where it is, overrides or not: in impure
  # evaluation always, in pure evaluation when it is in the store, which a
  # pure evaluation can read at all. A store copy at evaluation takes every
  # file, ignored ones too, and can be gigabytes; a build that needs the tree
  # copies it then. In place, a source in the store has the `outPath` the
  # flake evaluator gives it.
  rootInPlace = srcLocal != null && (isImpureEvaluation || isInStore (toString srcLocal.dir));

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
    mkSourceInfo :: (Path | String) -> AttrSet
    ```
  */
  mkSourceInfo = path: {
    lastModified = 0;
    lastModifiedDate = "19700101000000";
    outPath = inPlace path;
  };

  /**
    A directory as an `outPath` that copies nothing at evaluation.

    Outside the store it is a path value. `import` reads it where it is; a
    build that interpolates it gets a store copy, as with any path. A string
    would reach a builder as a directory outside its sandbox.

    A string in the store that has context keeps it, so a build uses it as
    it is. Context is not made up for one that has none: a flake's source in
    pure evaluation is a store path that is not in the store yet (Nix 2.35),
    and `appendContext` then names a path nothing can build.
    `builtins.storePath` checks validity, but fails pure evaluation and a
    virtual path with an error `tryEval` cannot catch. Such a path stays a
    path value. A build copies it again under a new name:
    `"${/nix/store/x-foo}"` is `/nix/store/<hash>-x-foo`.

    # Type

    ```
    inPlace :: (Path | String) -> (Path | String)
    ```
  */
  inPlace =
    dir:
    let
      dirString = toString dir;
      plain = builtins.unsafeDiscardStringContext dirString;
    in
    if builtins.isString dir && builtins.hasContext dir && isInStore plain then
      dir
    else if builtins.isPath dir then
      dir
    else
      /. + plain;

  overrideSubdirAttr = "__flakeCompatishSubdir";

  storePrefix = builtins.storeDir + "/";

  isInStore =
    pathString: builtins.substring 0 (builtins.stringLength storePrefix) pathString == storePrefix;

  /**
    A local tree named by `value`, or `null` when `value` names none.

    These name a local tree: a path, a string that starts with `/`, and an
    attrset with such an `outPath`, for example a flake or a `fetchTree`
    result. Any other string is a flake reference. A flake brings its
    `sourceInfo` along, and a `fetchTree` result is one, so the tree keeps its
    hash, revision and time.

    The result has `dir`, the directory in place, `sourceInfo`, and `subdir`,
    the part of `dir` below `sourceInfo.outPath`.

    # Type

    ```
    localTree :: Any -> AttrSet | Null
    ```
  */
  localTree =
    value:
    let
      outPath = if builtins.isAttrs value then value.outPath or null else value;
      isLocal =
        builtins.isPath outPath || builtins.isString outPath && builtins.substring 0 1 outPath == "/";
      dir = inPlace outPath;
      dirString = builtins.unsafeDiscardStringContext (toString dir);
      given =
        if !builtins.isAttrs value then
          null
        else if value ? sourceInfo then
          value.sourceInfo
        else if value ? narHash then
          value
        else
          null;
      givenRoot = builtins.unsafeDiscardStringContext (toString given.outPath);
      givenFits =
        given != null
        && (
          givenRoot == dirString
          || builtins.substring 0 (builtins.stringLength givenRoot + 1) dirString == givenRoot + "/"
        );
    in
    if !isLocal then
      null
    else
      {
        inherit dir;
        sourceInfo = if givenFits then given else mkSourceInfo dir;
        subdir =
          if givenFits && givenRoot != dirString then
            builtins.substring (builtins.stringLength givenRoot + 1) (-1) dirString
          else
            "";
      };

  /**
    The sourceInfo for one override value, or `null` when it cannot be used.

    A local tree (see `localTree`) that exists is used in place, and one that
    does not exist gives `null`. Any other string is a flake reference and is
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
    resolveOverride :: String -> Any -> AttrSet | Null
    ```
  */
  resolveOverride =
    name: override:
    let
      forcedOverride = builtins.tryEval override;
      local = if forcedOverride.success then builtins.tryEval (localTree forcedOverride.value) else forcedOverride;
      localExists =
        if local.success && local.value != null then
          builtins.tryEval (builtins.pathExists local.value.dir)
        else
          {
            success = false;
            value = false;
          };
    in
    if localExists.success && localExists.value then
      local.value.sourceInfo
      # An evaluated flake in a subdirectory names that directory, so the
      # lockfile's `dir` does not apply under it. `nodeLocations` takes the
      # attribute back out.
      // (if local.value.subdir == "" then { } else { ${overrideSubdirAttr} = local.value.subdir; })
    else if local.success && local.value != null then
      null
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

  # A flake without `flake.lock` has no inputs except `self`, which is the
  # lockfile the flake evaluator would write for it in memory.
  lockFile =
    if hasLockFile then
      builtins.fromJSON (builtins.readFile lockFilePath)
    else
      {
        nodes.root = { };
        root = "root";
        version = 7;
      };

  # The root's source when there is no `self` override. A path is copied to
  # the store here only in pure evaluation, and only from outside the store,
  # which pure evaluation refuses.
  rootSourceInfo =
    if sourceTree != null then
      sourceTree
    else if rootInPlace then
      srcLocal.sourceInfo
    else
      fcFetchTree {
        type = "path";
        path = sourceString;
      };

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
      builtins.warn "flake-compatish: ${sourceString}: overriding ${name} to ${toString sourceInfo.outPath}${
        if sourceInfo ? ${overrideSubdirAttr} then "/" + sourceInfo.${overrideSubdirAttr} else ""
      }${origin}" sourceInfo
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
          # Under tryEval: comparing with null forces the value, and
          # `<nixpkgs>` without a NIX_PATH entry throws here otherwise
          forced = builtins.tryEval candidate.value;
          sourceInfo =
            if !forced.success || forced.value == null then null else resolveOverride name forced.value;
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

  # The shortest chain of input names from the root to each node, for error
  # messages. A node can have several chains; `genericClosure` walks
  # breadth first and keeps the first.
  inputPaths = builtins.listToAttrs (
    map (item: {
      name = item.key;
      value = item.path;
    }) (
      builtins.genericClosure {
        startSet = [
          {
            key = lockFile.root;
            path = [ ];
          }
        ];
        operator =
          item:
          builtins.attrValues (
            builtins.mapAttrs (inputName: spec: {
              key = resolveInputSpec spec;
              path = item.path ++ [ inputName ];
            }) (lockFile.nodes.${item.key}.inputs or { })
          );
      }
    )
  );

  /**
    A node as a user names it, such as `` `tool → nixpkgs` (node `nixpkgs_2`) ``.
    The node name is left out when the last input name is the same.

    # Type

    ```
    describeNode :: String -> String
    ```
  */
  describeNode =
    nodeName:
    let
      path = inputPaths.${nodeName} or [ ];
      chain = builtins.concatStringsSep " → " path;
    in
    if path == [ ] then
      "node `${nodeName}`"
    else if builtins.elemAt path (builtins.length path - 1) == nodeName then
      "`${chain}`"
    else
      "`${chain}` (node `${nodeName}`)";

  ###########################################################################
  # Lockfile freshness
  ###########################################################################

  /**
    The input names a `flake.nix` declares: the keys of `inputs`, and the
    arguments of `outputs` except `self`. The flake evaluator locks an
    argument that `inputs` does not name as an indirect reference, so an
    argument is an input too, even with a default.

    # Type

    ```
    declaredInputNames :: AttrSet -> [String]
    ```
  */
  declaredInputNames =
    flake:
    let
      fromInputs = builtins.attrNames (flake.inputs or { });
      fromArgs = builtins.attrNames (builtins.functionArgs flake.outputs);
    in
    builtins.filter (name: name != "self") (
      fromInputs ++ builtins.filter (name: !(builtins.elem name fromInputs)) fromArgs
    );

  quoteNames = names: builtins.concatStringsSep ", " (map (name: "`${name}`") names);

  /**
    The root inputs that the lockfile has and `flake.nix` no longer
    declares. The flake evaluator drops them, and so does `evaluateNode`.

    Only the root: the lockfile can hold an input under a dependency that
    the dependency's `flake.nix` does not declare, for example after an
    override of a nested input.

    # Type

    ```
    staleInputNames :: String -> AttrSet -> AttrSet -> [String]
    ```
  */
  staleInputNames =
    nodeName: node: flake:
    let
      declared = declaredInputNames flake;
    in
    if nodeName != lockFile.root then
      [ ]
    else
      builtins.filter (name: !(builtins.elem name declared)) (builtins.attrNames (node.inputs or { }));

  /**
    `value`, or an error when the lockfile cannot serve `flake`.

    The flake evaluator locks a declared input that the lockfile lacks.
    flake-compatish cannot lock, so that is an error that says to run
    `nix flake lock`. Without this check, the error is a missing argument of
    `outputs`, which does not name the lockfile.

    A stale input, which the flake evaluator drops, gets a warning.

    # Inputs

    `nodeName`
    : The lockfile node of `flake`.

    `node`
    : That node.

    `flakeDir`
    : Where `flake` is, for the message.

    `flake`
    : The imported `flake.nix`.

    `value`
    : What to return when the lockfile is current.

    # Type

    ```
    checkLockFresh :: String -> AttrSet -> String -> AttrSet -> a -> a
    ```
  */
  checkLockFresh =
    nodeName: node: flakeDir: flake: value:
    let
      isRootNode = nodeName == lockFile.root;
      declared = declaredInputNames flake;
      locked = builtins.attrNames (node.inputs or { });
      missing = builtins.filter (name: !(builtins.elem name locked)) declared;
      stale = staleInputNames nodeName node flake;
      where = if isRootNode then lockFilePath else "node `${nodeName}` of ${lockFilePath}";
    in
    if missing != [ ] && !hasLockFile then
      throw (
        "flake-compatish: ${toString flakeDir}/flake.nix declares inputs, and there is no flake.lock: "
        + "${quoteNames missing}. Run `nix flake lock`."
      )
    else if missing != [ ] then
      throw (
        "flake-compatish: ${toString flakeDir}/flake.nix declares inputs that ${where} does not have: "
        + "${quoteNames missing}. Run `nix flake lock`."
        + (
          if isRootNode then
            ""
          else
            " An override can supply a newer flake than the lockfile knows; lock with that override."
        )
      )
    else if stale != [ ] then
      builtins.warn (
        "flake-compatish: ${lockFilePath} has inputs that ${toString flakeDir}/flake.nix does not declare: "
        + "${quoteNames stale}. flake-compatish ignores them. Run `nix flake lock`."
      ) (warnChangedUrls nodeName flakeDir flake value)
    else
      warnChangedUrls nodeName flakeDir flake value;

  /**
    `value`, with a warning for each root input whose `url` no longer gives
    the reference the lockfile recorded. The flake evaluator fetches the new
    reference; flake-compatish uses the locked one.

    Only the root, and only inputs with a `url`: an input of a dependency
    can be overridden from the root's `flake.nix`, and an input without a
    `url` gets a default reference that this does not compute.

    # Type

    ```
    warnChangedUrls :: String -> String -> AttrSet -> a -> a
    ```
  */
  warnChangedUrls =
    nodeName: flakeDir: flake: value:
    let
      inputs = flake.inputs or { };
      lockedInputs = lockFile.nodes.${lockFile.root}.inputs or { };
      changed = builtins.filter (
        name:
        let
          declared = inputs.${name};
          spec = lockedInputs.${name} or null;
        in
        builtins.isAttrs declared
        && declared ? url
        && builtins.isString spec
        && fcParseFlakeRef declared.url != (lockFile.nodes.${spec}.original or null)
      ) (builtins.attrNames inputs);
    in
    if nodeName != lockFile.root || changed == [ ] then
      value
    else
      builtins.warn (
        "flake-compatish: ${toString flakeDir}/flake.nix changes the url of ${quoteNames changed}, "
        + "and ${lockFilePath} still has the old reference. flake-compatish uses the locked one. "
        + "Run `nix flake lock`."
      ) value;

  ###########################################################################
  # Node evaluation
  ###########################################################################

  /**
    Whether a locked input is a relative `path:`.

    A `path:` input can be written relative to the flake that declares it,
    and the lockfile keeps it that way. `parent` records the chain of input
    names from the root to that flake, and an empty chain means the root
    itself.

    # Type

    ```
    isRelativePath :: AttrSet -> Bool
    ```
  */
  isRelativePath =
    locked: (locked.type or "") == "path" && builtins.substring 0 1 (locked.path or "/") != "/";

  /**
    Where a node is, before its flake is evaluated:

    - `sourceInfo`: the tree, fetched or used in place.
    - `outPath`: the flake's directory, which is not `sourceInfo.outPath`
      when the flake is in a subdirectory.
    - `relativeBase`: the directory that a relative `path:` input of this
      flake starts from.
    - `isolated`: whether `sourceInfo` holds this directory only, without
      its siblings.

    This follows `call-flake.nix` of the flake evaluator. An override wins.
    A relative input is in its parent's tree: it takes the parent's
    sourceInfo, and its directory is under the parent's directory. So it is
    not fetched, and an override of the parent moves it.

    A `path:` source is copied to the store without its siblings, and the
    flake evaluator cannot reach a sibling from there. flake-compatish
    starts from the original directory instead, and copies each relative
    input by itself.

    It is separate from `evaluatedNodes`, so a child reads its parent's
    directory without forcing the parent's outputs.

    # Type

    ```
    nodeLocations :: AttrSet
    ```
  */
  nodeLocations = builtins.mapAttrs (
    nodeName: node:
    let
      isRootNode = nodeName == lockFile.root;
      # Inside the context: a string override is fetched while it resolves.
      resolvedOverride = withNodeContext "fetching" nodeName (
        if isRootNode then resolveNamedOverride "self" else resolveNodeOverride nodeName node
      );
      override =
        if resolvedOverride == null then null else removeAttrs resolvedOverride [ overrideSubdirAttr ];
      overrideSubdir = if resolvedOverride == null then null else resolvedOverride.${overrideSubdirAttr} or null;
      isRelative = !isRootNode && override == null && isRelativePath node.locked;
      parent = nodeLocations.${followPath lockFile.root (node.parent or [ ])};
      inParentTree = isRelative && !parent.isolated;
      subdir =
        if overrideSubdir != null then
          overrideSubdir
        else if !isRootNode then
          node.locked.dir or ""
        else if override == null then
          sourceDir
        else
          "";
      withSubdir = dir: dir + (if subdir == "" then "" else "/" + subdir);
      relativeDir = parent.relativeBase + (if node.locked.path == "" then "" else "/" + node.locked.path);

      sourceInfo = withNodeContext "fetching" nodeName (
        if override != null then
          override
        else if isRootNode then
          rootSourceInfo
        else if inParentTree then
          parent.sourceInfo
        else if isRelative then
          fcFetchTree {
            type = "path";
            path = relativeDir;
          }
        else
          fcFetchTree (node.info or { } // removeAttrs node.locked [ "dir" ])
      );

      outPath = if inParentTree then relativeDir else withSubdir sourceInfo.outPath;
      copiedPath =
        override == null
        && (if isRootNode then sourceTree == null && !rootInPlace else node.locked.type or "" == "path");
    in
    {
      inherit sourceInfo outPath;
      isolated = copiedPath && !inParentTree;
      relativeBase =
        if !copiedPath || inParentTree then
          outPath
        else if isRootNode then
          withSubdir sourceString
        else if isRelative then
          withSubdir relativeDir
        else
          withSubdir node.locked.path;
    }
  ) lockFile.nodes;

  /**
    `value`, with error context that names the input of a node. The root
    needs none: its errors name its files.

    # Type

    ```
    withNodeContext :: String -> String -> a -> a
    ```
  */
  withNodeContext =
    step: nodeName: value:
    if nodeName == lockFile.root then
      value
    else
      builtins.addErrorContext "while ${step} the flake input ${describeNode nodeName}" value;

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
      withContext = step: withNodeContext step nodeName;
      inherit (nodeLocations.${nodeName}) sourceInfo;
      flakePath = nodeLocations.${nodeName}.outPath;

      flake = withContext "evaluating" (import (flakePath + "/flake.nix"));

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
      ) (removeAttrs (node.inputs or { }) (staleInputNames nodeName node flake));

      # Call flake.outputs with resolved inputs + self reference
      flakeOutputs = withContext "evaluating" (
        checkLockFresh nodeName node flakePath flake (
          flake.outputs (resolvedInputs // { self = flakeResult; })
        )
      );

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
          outPath = flakePath;
          inputs = resolvedInputs;
          outputs = flakeOutputs;
          inherit sourceInfo;
          _type = "flake";
        }
        // (if injectedLegacyPackages != null then { legacyPackages = injectedLegacyPackages; } else { });

    in
    if node.flake or true then
      assert builtins.isFunction flake.outputs;
      flakeResult
    else
      sourceInfo
      // {
        inherit sourceInfo;
        outPath = flakePath;
      };

  ###########################################################################
  # Main entry point
  ###########################################################################

  rootFlake =
    if lockFile.version >= 5 && lockFile.version <= 7 then
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
        _: inputSpec:
        let
          location = nodeLocations.${resolveInputSpec inputSpec};
        in
        location.sourceInfo // { inherit (location) outPath; }
      ) lockFile.nodes.${lockFile.root}.inputs or { }
    else
      { };
}
