{
  inputs = { };
  outputs = { self }: {
    testValue = "hello from simple";
    selfPath = self.outPath;
  };
}
