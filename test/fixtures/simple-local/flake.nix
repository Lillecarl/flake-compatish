{
  inputs = { };
  outputs =
    { self }:
    {
      testValue = "hello from simple-local";
      selfPath = self.outPath;
      legacyPackages = {
        x86_64-linux.marker = "simple-local-override";
      };
      legacyMarker = self.legacyPackages.x86_64-linux.marker;
    };
}
