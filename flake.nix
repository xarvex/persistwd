{
  description = "persistwd helps keep passwords persistent for non-mutable user setups";

  inputs = {
    devenv.url = "github:cachix/devenv";

    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
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
      imports = [ inputs.devenv.flakeModule ];

      systems = import inputs.systems;

      perSystem =
        { pkgs, ... }:
        let
          manifest = (lib.importTOML ./Cargo.toml).package;
        in
        {
          packages = rec {
            default = persistwd;

            persistwd = pkgs.rustPlatform.buildRustPackage rec {
              pname = manifest.name;
              inherit (manifest) version;

              src = ./.;
              cargoLock.lockFile = ./Cargo.lock;

              nativeBuildInputs = with pkgs; [ rustPlatform.bindgenHook ];
              buildInputs = with pkgs; [ glibc.dev ];

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
                # If not overridden (/dev/null), --impure is necessary.
                lib.mkIf (devenvRoot != "") devenvRoot;

              name = "persistwd";

              packages = with pkgs; [
                cargo-deny
                cargo-edit
                cargo-msrv
                cargo-udeps

                codespell

                glibc.dev
                rustPlatform.bindgenHook
              ];

              languages = {
                nix.enable = true;
                rust.enable = true;
              };

              pre-commit.hooks = {
                clippy.enable = true;
                deadnix.enable = true;
                flake-checker.enable = true;
                nixfmt-rfc-style.enable = true;
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
            cfg' = config.security.shadow;
            cfg = cfg'.persistwd;

            selfPkgs = self.packages.${pkgs.system};
            tomlFormat = pkgs.formats.toml { };
          in
          {
            options.security.shadow.persistwd = {
              enable = lib.mkEnableOption "persistwd";
              package = lib.mkPackageOption selfPkgs "persistwd" { };

              users = lib.mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                example = [
                  "root"
                  "xarvex"
                ];
                description = ''
                  Users for persistwd to manage.
                  This will configure users.users.<user>.hashedPasswordFile for each user.
                '';
              };
              directory = lib.mkOption {
                type = lib.types.str;
                default = "/etc/persistwd/shadow";
                example = "/var/lib/persistwd/shadow";
                description = ''
                  The directory to put user shadow files.
                  This affects users.users.<user>.hashedPasswordFile.
                  Only relevant for the users set in security.shadow.persistwd.users.
                '';
              };
              volume = lib.mkOption {
                type = lib.types.str;
                default = "";
                example = "/persist";
                description = ''
                  The volume path to put before the users.users.<user>.hashedPasswordFile path.
                  Only relevant for the users set in security.shadow.persistwd.users.
                  This option is important because /etc/shadow is set up before persist mounts are made.
                '';
              };
              settings = lib.mkOption {
                inherit (tomlFormat) type;
                example = lib.literalExpression ''
                  {
                    users = {
                      root = "/etc/persistwd/shadow/root";
                      xarvex = "/etc/persistwd/shadow/xarvex";
                    };
                  };
                '';
                description = "Configuration used for persistwd.";
              };
            };

            config = lib.mkIf (cfg'.enable && cfg.enable) {
              assertions = [
                {
                  assertion = !config.users.mutableUsers;
                  message = "persistwd only has a purpose with non-mutable users";
                }
              ];

              environment.etc."persistwd/config.toml".source =
                tomlFormat.generate "persistwd-settings" cfg.settings;

              security = {
                shadow.persistwd.settings.users = lib.genAttrs cfg.users (
                  user: config.users.users.${user}.hashedPasswordFile
                );

                wrappers.passwd = {
                  setuid = true;
                  owner = "root";
                  group = "root";
                  source = "${config.security.loginDefs.package.out}/bin/passwd";
                };
              };

              systemd.services.persistwd = {
                description = "persistwd";
                after = [ "multi-user-pre.target" ];
                partOf = [ "multi-user.target" ];
                serviceConfig.ExecStart = "${lib.getExe cfg.package} watch";
                wantedBy = [ "multi-user.target" ];
              };

              users.users = lib.genAttrs cfg.users (user: {
                hashedPasswordFile = lib.mkDefault "${cfg.volume}${cfg.directory}/${user}";
              });
            };
          };
      };
    };
}
