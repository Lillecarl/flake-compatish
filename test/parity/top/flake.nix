{
  inputs = {
    leaf.url = "path:../leaf";
    mid = {
      url = "path:../mid";
      inputs.leaf.follows = "leaf";
    };
  };
  outputs =
    {
      self,
      leaf,
      mid,
    }:
    {
      value = "top";
      selfOutPath = self.outPath;
      midLeafOutPath = mid.leafOutPath;
      leafOutPath = leaf.outPath;
      inherit (mid) nestedValue dataText;
    };
}
