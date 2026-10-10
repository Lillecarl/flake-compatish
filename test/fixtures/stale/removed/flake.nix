# The lockfile still has `simple`, which this flake no longer declares.
{
  inputs = { };
  outputs =
    { self, ... }:
    {
      testValue = "hello from stale/removed";
    };
}
