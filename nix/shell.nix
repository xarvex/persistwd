{ pkgs, ... }:

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    cargo
    rustc

    rustPlatform.bindgenHook

    clippy
    rust-analyzer
    rustfmt

    cargo-deny
    cargo-edit
    cargo-expand
    cargo-msrv
    cargo-sort
    cargo-udeps

    deadnix
    flake-checker
    nixfmt-rfc-style
    statix

    pre-commit
  ];
  buildInputs = with pkgs; [ glibc.dev ];

  env = {
    RUST_BACKTRACE = 1;
    RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
  };

  shellHook = ''
    pre-commit install
  '';
}
