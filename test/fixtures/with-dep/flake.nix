{
  inputs = {
    simple.url = "path:../simple";
    nixpkgs.url = "path:../fake-nixpkgs";
  };
  outputs =
    {
      self,
      simple,
      nixpkgs,
    }:
    {
      testValue = "hello from with-dep";
      simpleValue = simple.testValue;
      selfPath = self.outPath;
      simplePath = simple.outPath;
      legacyPackages = {
        x86_64-linux.marker = "with-dep-local";
      };
      selfLegacyMarker = self.legacyPackages.x86_64-linux.marker;
      simpleLegacyMarker = simple.legacyMarker;
    };
}
