/**
  The documentation: the README as the front page, and an API reference that
  nixdoc generates from the doc comments.

  `nix build --file ./doc api` builds the reference as Markdown, and
  `nix build --file ./doc site` builds the HTML site that GitHub Pages
  serves.
*/
{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;

  /**
    The reference as nixdoc writes it.
  */
  api = pkgs.runCommand "flake-compatish-api.md" { nativeBuildInputs = [ pkgs.nixdoc ]; } ''
    {
      nixdoc --prefix flake-compatish --category default --description "default.nix" --file ${../default.nix}
      nixdoc --prefix flake-compatish --category lib --description "lib.nix" --file ${../lib.nix}
      nixdoc --prefix flake-compatish --category core --description "nix/core.nix" --file ${../nix/core.nix}
      nixdoc --prefix flake-compatish --category overridable --description "nix/overridable.nix" --file ${../nix/overridable.nix}
    } > $out
  '';

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.sphinx
    ps.myst-parser
    ps.furo
  ]);
in
{
  inherit api;

  /**
    The HTML site. Sphinx runs with `-W`, so a warning fails the build.
  */
  site = pkgs.stdenvNoCC.mkDerivation {
    name = "flake-compatish-site";
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        ../README.md
        ./conf.py
        ./index.md
        ./nixdoc_to_myst.py
      ];
    };
    nativeBuildInputs = [ pythonEnv ];
    buildPhase = ''
      runHook preBuild
      python3 -I doc/nixdoc_to_myst.py < ${api} > doc/api.md
      sphinx-build -b html -W -d "$TMPDIR/doctrees" doc "$out"
      rm "$out/.buildinfo"
      runHook postBuild
    '';
    dontInstall = true;
  };
}
