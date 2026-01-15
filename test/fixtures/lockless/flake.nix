{
  inputs = { };
  outputs = { self }: {
    testValue = "hello from lockless";
    selfPath = self.outPath;
  };
}
