{
  inputs = {
    simple.url = "path:../simple";
  };
  outputs = { self, simple }: {
    testValue = "hello from with-dep";
    simpleValue = simple.testValue;
    selfPath = self.outPath;
    simplePath = simple.outPath;
  };
}
