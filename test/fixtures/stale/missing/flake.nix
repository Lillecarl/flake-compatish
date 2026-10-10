# The lockfile has `simple` only. `another` is in `inputs`, and `extra` is
# only an argument of `outputs`, which the flake evaluator also locks.
{
  inputs = {
    simple.url = "path:../../simple";
    another.url = "path:../../lockless";
  };
  outputs =
    {
      self,
      simple,
      another,
      extra,
    }:
    {
      testValue = "hello from stale/missing";
    };
}
