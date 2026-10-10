{
  outputs =
    { self }:
    {
      value = "leaf";
      selfOutPath = self.outPath;
    };
}
