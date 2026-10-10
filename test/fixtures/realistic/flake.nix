# Shaped like a real repository: nixpkgs from GitHub, and a tool that brings
# its own nixpkgs, which the lockfile keeps as a second node. Nothing here
# is fetched; every test overrides each GitHub input.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tool.url = "github:Example/Tool";
  };
  outputs =
    {
      self,
      nixpkgs,
      tool,
    }:
    {
      rootMarker = nixpkgs.legacyPackages.x86_64-linux.marker;
      toolMarker = tool.nixpkgsMarker;
    };
}
