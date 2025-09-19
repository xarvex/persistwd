{ self, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg' = config.security.shadow;
  cfg = cfg'.persistwd;

  tomlFormat = pkgs.formats.toml { };
in
{
  options.security.shadow.persistwd = {
    enable = lib.mkEnableOption "persistwd";
    package = lib.mkPackageOption self.packages.${pkgs.system} "persistwd" { };

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
      default = { };
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

    environment = {
      systemPackages = with cfg; [ package ];
      etc."persistwd/config.toml".source = lib.mkIf (cfg.settings != { }) (
        tomlFormat.generate "persistwd-settings" cfg.settings
      );
    };

    security = {
      shadow.persistwd.settings.users = lib.genAttrs cfg.users (
        user: config.users.users.${user}.hashedPasswordFile
      );

      wrappers.passwd = {
        source = "${config.security.loginDefs.package.out}/bin/passwd";
        setuid = true;
        owner = "root";
        group = "root";
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
}
