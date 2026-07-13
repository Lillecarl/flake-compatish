{
  pkgs ? import <nixpkgs> { },
}:
pkgs.callPackage ./nix/shell.nix { }
