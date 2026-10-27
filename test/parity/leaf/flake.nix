{
  outputs =
    { self }:
    {
      value = "leaf";
      selfOutPath = self.outPath;
      selfSourceInfo = removeAttrs self.sourceInfo [ "outPath" ];
      # Every other output, for one `nix eval --json` in test/pure-parity.sh.
      all = removeAttrs self.outputs [ "all" ];
    };
}
