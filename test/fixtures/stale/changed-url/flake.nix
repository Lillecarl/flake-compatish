# The lockfile has `simple` at ../../simple. The url now names lockless.
{
  inputs = {
    simple.url = "path:../../lockless";
  };
  outputs =
    { self, simple }:
    {
      simpleValue = simple.testValue;
    };
}
