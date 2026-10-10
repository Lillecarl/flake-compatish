# Reached as `?dir=sub`, so the flake is in a subdirectory of its source.
{
  outputs =
    { self }:
    {
      value = "nested";
      selfOutPath = self.outPath;
    };
}
