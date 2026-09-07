# Two levels down. `simple` is not an input of this flake -- it is an input
# of `with-dep`, which is. So an override keyed by name cannot reach it and
# `reroot` can.
{
  inputs = {
    with-dep.url = "path:../with-dep";
  };
  outputs =
    {
      self,
      with-dep,
    }:
    {
      testValue = "hello from deep";
      selfPath = self.outPath;

      # Reported by with-dep about its own input, so this reads the same
      # under the flake evaluator and under flake-compatish.
      nestedSimplePath = with-dep.simplePath;
      nestedSimpleValue = with-dep.simpleValue;
    };
}
