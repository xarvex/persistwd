{
  description = "persistwd helps keep passwords persistent for non-mutable user setups";

  inputs = {
    devenv.url = "github:cachix/devenv";

    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    {
      flake-parts,
      nixpkgs,
      self,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.devenv.flakeModule ];

      systems = import inputs.systems;

      perSystem =
        { pkgs, ... }:
        let
          inherit (nixpkgs) lib;

          manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
        in
        {
          packages = rec {
            default = persistwd;

            persistwd = pkgs.rustPlatform.buildRustPackage rec {
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

          devenv.shells = rec {
            default = persistwd;

            persistwd = {
              devenv.root =
                let
                  devenvRoot = builtins.readFile inputs.devenv-root.outPath;
                in
                # If not overriden (/dev/null), --impure is necessary.
                lib.mkIf (devenvRoot != "") devenvRoot;

              name = "persistwd";

              packages = with pkgs; [
                cargo-deny
                cargo-edit
                cargo-msrv
                cargo-udeps
              ];

              languages = {
                nix.enable = true;
                rust = {
                  enable = true;
                  channel = "stable";
                };
              };

              pre-commit.hooks = {
                clippy.enable = true;
                deadnix.enable = true;
                flake-checker.enable = true;
                nixfmt = {
                  enable = true;
                  package = pkgs.nixfmt-rfc-style;
                };
                rustfmt.enable = true;
                statix.enable = true;
              };
            };
          };

          formatter = pkgs.nixfmt-rfc-style;
        };

      flake.nixosModules = rec {
        default = persistwd;

        persistwd =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.security.shadow.persistwd;

            selfPkgs = self.packages.${pkgs.system};
            tomlFormat = pkgs.formats.toml { };
          in
          {
            options.security.shadow.persistwd = {
              enable = lib.mkEnableOption "persistwd";
              package = lib.mkPackageOption selfPkgs "persistwd" { };
              settings = lib.mkOption {
                inherit (tomlFormat) type;

                default = {
                  users = builtins.mapAttrs (_: value: value.hashedPasswordFile) (
                    lib.filterAttrs (
                      _: value: value.isNormalUser || value.uid == config.ids.uids.root
                    ) config.users.users
                  );
                };
                example = lib.literalExpression ''
                  {
                    users = {
                      root = "/persist/etc/shadow/root";
                      xarvex = "/persist/etc/shadow/xarvex";
                    };
                  };
                '';
                description = "Configuration used for persistwd.";
              };
            };

            config = lib.mkIf (config.security.shadow.enable && cfg.enable) {
              assertions = [
                {
                  assertion = !config.users.mutableUsers;
                  message = "persistwd only has a purpose with non-mutable users";
                }
              ];

              security.wrappers.passwd = {
                setuid = true;
                owner = "root";
                group = "root";
                source = "${config.security.loginDefs.package.out}/bin/passwd";
              };

              systemd.services.persistwd = {
                enable = true;
                unitConfig = {
                  Description = [ "persistwd" ];
                  After = [ "multi-user-pre.target" ];
                  PartOf = [ "multi-user.target" ];
                };
                serviceConfig.ExecStart = "${lib.getExe cfg.package} -c ${tomlFormat.generate "persistwd-settings" cfg.settings}";
                wantedBy = [ "multi-user.target" ];
              };
            };
          };
      };
    };
}
