{
  inputs = {
    leaf.url = "path:../leaf";
    # Not `path:../nested?dir=sub`: the flake evaluator ignores `dir` on a
    # relative path (Nix 2.35).
    nested.url = "path:../nested/sub";
    data = {
      url = "path:../data";
      flake = false;
    };
  };
  outputs =
    {
      self,
      leaf,
      nested,
      data,
    }:
    {
      value = "mid";
      selfOutPath = self.outPath;
      leafValue = leaf.value;
      leafOutPath = leaf.outPath;
      nestedValue = nested.value;
      nestedOutPath = nested.outPath;
      dataText = builtins.readFile "${data}/data.txt";
      dataOutPath = data.outPath;
    };
}
