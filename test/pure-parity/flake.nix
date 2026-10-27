# The second flake of test/pure-parity.sh. It has no inputs, and evaluates
# the flakes in ../parity with flake-compatish, in pure evaluation. The
# script compares each result with what the flake evaluator gives for the
# same flake.
{
  outputs =
    { self }:
    let
      flake-compatish = import ../../.;
      names = [
        "leaf"
        "mid"
        "top"
      ];
      forAll =
        f:
        builtins.listToAttrs (
          map (name: {
            inherit name;
            value = (f name).outputs.all;
          }) names
        );
    in
    {
      # The flake evaluator gives a flake in a subdirectory the sourceInfo of
      # the whole tree. This source carries it, so all of the result matches.
      withSourceInfo = forAll (
        name:
        flake-compatish {
          source = {
            outPath = self.sourceInfo.outPath + "/test/parity/${name}";
            inherit (self) sourceInfo;
          };
        }
      );
      # Strings, as `self.outPath + ...` gives them.
      fromString = forAll (
        name: flake-compatish { source = self.sourceInfo.outPath + "/test/parity/${name}"; }
      );
      # Path values, as `./.` gives them.
      fromPath = forAll (name: flake-compatish { source = ../parity + "/${name}"; });
    };
}
