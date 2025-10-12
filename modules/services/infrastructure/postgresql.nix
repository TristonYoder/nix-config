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
  };

  config = mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      dataDir = cfg.dataDir;
      enableTCPIP = cfg.enableTCPIP;
    };
  };
}

