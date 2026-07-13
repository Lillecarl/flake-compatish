{ mkShell, nixfmt }:
mkShell {
  packages = [
    nixfmt
  ];
}
