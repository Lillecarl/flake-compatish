# Read through NIX_PATH by test/realistic.nix, which runs with HOME set to
# test/fixtures, so `~` names the fixtures. Pure evaluation never reads this
# file, so `~` is safe here.
{
  "github:NixOS/nixpkgs" = ~/fake-nixpkgs;
  "github:Example/Tool" = ~/realistic-tool;
}
