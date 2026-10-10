{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
  outputs =
    { self, nixpkgs }:
    {
      nixpkgsMarker = nixpkgs.legacyPackages.x86_64-linux.marker;
    };
}
