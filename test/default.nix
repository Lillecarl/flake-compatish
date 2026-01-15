let
  flake =
    let
      # lockFile = builtins.readFile ./flake.lock;
      # lockAttrs = builtins.fromJSON lockFile;
      # fcLockInfo = lockAttrs.nodes.flake-compatish.locked;
      # fcSrc = builtins.fetchTree fcLockInfo;
      # flake-compatish = import fcSrc;
      flake-compatish = import ../.;
    in
    flake-compatish {
      source = ./.;
      overrides = {
        self = ./.;
        nixpkgs = /home/lillecarl/Code/nixpkgs;
      };
    };
in
flake
