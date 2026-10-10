# Declares an input and has no flake.lock.
{
  inputs = {
    simple.url = "path:../../simple";
  };
  outputs =
    { self, simple }:
    {
      testValue = "hello from stale/lockless-inputs";
    };
}
