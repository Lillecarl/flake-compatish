# The lockfile still has `simple`, which this flake no longer declares. No
# `...`: an extra argument would fail, so this proves that it is dropped.
{
  inputs = { };
  outputs =
    { self }:
    {
      testValue = "hello from stale/removed";
    };
}
