{
  outputs =
    { self }:
    {
      legacyPackages = {
        x86_64-linux = import ./default.nix { system = "x86_64-linux"; };
      };
    };
}
