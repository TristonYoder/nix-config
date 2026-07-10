{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.postgresql;
in
{
  options.modules.services.infrastructure.postgresql = {
    enable = mkEnableOption "PostgreSQL database server";
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/postgres";
      description = "PostgreSQL data directory";
    };
    
    enableTCPIP = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TCP/IP connections";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.postgresql_16;
      defaultText = literalExpression "pkgs.postgresql_16";
      description = ''
        PostgreSQL package to run. Bumping the major version against an
        existing data directory requires a manual dump/restore migration
        first — NixOS will not do this for you, and the service will refuse
        to start against an incompatible on-disk cluster. See the NixOS
        manual's "Upgrading" section under services.postgresql.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = cfg.package;
      dataDir = cfg.dataDir;
      enableTCPIP = cfg.enableTCPIP;
    };
  };
}

