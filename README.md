# flake-compat

## Goals
Be able to consume modern flakes without hating your life. This means you should
be able to build your things with flakes, or with flake-compatish and expect
similar results (but not 100% equal).

## Non-goals
Purity, cross compiling, being an exact clone of flakes.

## Differences
flake-compatish avoids copying things to store before evaluating, this is true
for src as well as path: type flake inputs. For path: we just fake as little as
possible to make evaluation work, this is useful when hacking on a big dependency
like nixpkgs. Don't commit your lockfile when doing this unless you're a master
hacker.

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
# outputs.packages.x86_64-linux.hello = derivation
# impure.packages.hello = derivation
```
