{
  description = "persistwd helps keep passwords persistent for non-mutable user setups";

  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      self,
      ...
    }:
    let
      inherit (nixpkgs) lib;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        { pkgs, ... }:
        {
          packages = rec {
            default = persistwd;
            persistwd = pkgs.callPackage ./nix/package.nix { };
          };

          devShells = rec {
            default = persistwd;
            persistwd = import ./nix/shell.nix {
              inherit
                inputs
                lib
                pkgs
                self
                ;
            };
          };

          formatter = pkgs.nixfmt-rfc-style;
        };

      flake.nixosModules = rec {
        default = persistwd;
        persistwd = import ./nix/nixos.nix { inherit inputs self; };
      };
    };
}
