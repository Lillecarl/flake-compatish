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
      selfSourceInfo = removeAttrs self.sourceInfo [ "outPath" ];
      midOutPath = mid.outPath;
      midSourceInfo = removeAttrs mid.sourceInfo [ "outPath" ];
      midAll = mid.all;
      # Every other output, for one `nix eval --json` in test/pure-parity.sh.
      all = removeAttrs self.outputs [ "all" ];
    };
}
