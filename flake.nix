{
  description = "persistwd helps keep passwords persistent for non-mutable user setups";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    systems.url = "github:nix-systems/default-linux";
  };

  outputs = { flake-parts, nixpkgs, self, systems, ... }@inputs: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = import systems;

    perSystem = { system, ... }:
      let
        inherit (nixpkgs) lib;

        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default =
          pkgs.rustPlatform.buildRustPackage
            rec {
              pname = "persistwd";
              version = "0.0.1";

              src = ./.;
              cargoLock.lockFile = ./Cargo.lock;

              meta = {
                description = "persistwd helps keep passwords persistent for non-mutable user setups";
                homepage = "https://gitlab.com/xarvex/persistwd";
                license = lib.licenses.mit;
                maintainers = with lib.maintainers; [ xarvex ];
                mainProgram = pname;
                platforms = lib.platforms.linux;
              };
            };
      };

    flake.nixosModules.default = ({ config, lib, pkgs, ... }: lib.mkIf (!config.users.mutableUsers) {
      security.wrappers.passwd = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${config.security.loginDefs.package.out}/bin/passwd";
      };

      environment.etc."persistwd/config.toml".source = (pkgs.formats.toml { }).generate "config.toml" {
        users = {
          xarvex = "/persist/etc/shadow/xarvex";
        };
      };

      systemd.services.persistwd = rec {
        enable = true;
        description = "persistwd helps keep passwords persistent for non-mutable user setups";
        unitConfig = {
          Description = [ description ];
          After = [ "multi-user-pre.target" ];
          PartOf = [ "multi-user.target" ];
        };
        serviceConfig.ExecStart = lib.getExe self.packages.${pkgs.system}.default;
        wantedBy = [ "multi-user.target" ];
      };
    });
  };
}
