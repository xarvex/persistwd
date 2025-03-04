{ pkgs, self, ... }:

let
  inherit (self.checks.${pkgs.system}) pre-commit;
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    cargo
    rustc

    rustPlatform.bindgenHook
  ];
  buildInputs =
    pre-commit.enabledPackages
    ++ (with pkgs; [
      glibc.dev

      clippy
      rust-analyzer

      cargo-deny
      cargo-edit
      cargo-expand
      cargo-msrv
      cargo-udeps
    ]);

  env = {
    RUST_BACKTRACE = 1;
    RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
  };

  inherit (pre-commit) shellHook;
}
