{
  inputs = { };
  outputs =
    { self }:
    {
      testValue = "hello from simple";
      selfPath = self.outPath;
      legacyPackages = {
        x86_64-linux.marker = "simple-local";
      };
      legacyMarker = self.legacyPackages.x86_64-linux.marker;
    };
}
