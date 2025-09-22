# flake-compat

## Usage

default.nix
```nix
let
  fc = import (builtins.fetchTree {
    type = "git";
    url = "https://github.com/lillecarl/flake-compatish.git";
  });
in
fc ./.
```

flake-compatish only supports evaluating from filesystem (not store) and relies
on your Nix being modern enough and configured to support builtins.fetchTree.
