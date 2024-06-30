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
        manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
      in
      {
        packages = rec {
          default = persistwd;
          persistwd =
            pkgs.rustPlatform.buildRustPackage
              rec {
                inherit (manifest) version;

                pname = manifest.name;

                src = pkgs.lib.cleanSource ./.;
                cargoLock.lockFile = ./Cargo.lock;

                meta = {
                  inherit (manifest) description;

                  homepage = manifest.repository;
                  license = lib.licenses.mit;
                  maintainers = with lib.maintainers; [ xarvex ];
                  mainProgram = pname;
                  platforms = lib.platforms.linux;
                };
              };
        };
      };

    flake.nixosModules.default = ({ config, lib, pkgs, ... }:
      let
        selfPkgs = self.packages.${pkgs.system};
        tomlFormat = pkgs.formats.toml { };
      in
      {
        options.security.shadow.persistwd = {
          enable = lib.mkEnableOption "persistwd";
          package = lib.mkPackageOption selfPkgs "persistwd" { };
          settings = lib.mkOption {
            type = tomlFormat.type;
            default = {
              users = builtins.mapAttrs (name: value: value.hashedPasswordFile)
                (lib.filterAttrs (name: value: value.isNormalUser || value.uid == config.ids.uids.root) config.users.users);
            };
            example = lib.literalExpression ''
              {
                users = {
                  root = "/persist/etc/shadow/root";
                  xarvex = "/persist/etc/shadow/xarvex";
                };
              };
            '';
            description = ''
              Configuration written to {file}`/etc/persistwd/config.toml`
            '';
          };
        };

        config =
          let
            cfg = config.security.shadow.persistwd;
          in
          lib.mkIf (config.security.shadow.enable && cfg.enable) {
            assertions = [{
              assertion = !config.users.mutableUsers;
              message = "persistwd only has a purpose with non-mutable users";
            }];

            security.wrappers.passwd = {
              setuid = true;
              owner = "root";
              group = "root";
              source = "${config.security.loginDefs.package.out}/bin/passwd";
            };

            systemd.services.persistwd = {
              enable = true;
              unitConfig = {
                Description = [ selfPkgs.persistwd.meta.description ];
                After = [ "multi-user-pre.target" ];
                PartOf = [ "multi-user.target" ];
              };
              serviceConfig.ExecStart = lib.getExe cfg.package;
              wantedBy = [ "multi-user.target" ];
            };

            environment.etc."persistwd/config.toml".source = tomlFormat.generate "persistwd-settings" cfg.settings;
          };
      });
  };
}
