# A local overrides file that uses `~`. Nix rejects `~` in pure mode while
# parsing, so test/flake.nix also proves pure evaluation never reads it.
{
  simple = ~/lockless;
}
