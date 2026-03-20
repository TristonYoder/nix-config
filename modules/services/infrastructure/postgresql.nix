{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.postgresql;
  helpers = import ../../lib.nix { inherit lib; };
in
{
  options.modules.services.infrastructure.postgresql = {
    enable = mkEnableOption "PostgreSQL database server";

    serviceName = mkOption {
      type = types.str;
      default = "postgres";
      description = "Service name used for appData registration";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${config.modules.services.appData.mount}/${config.modules.services.appData.services.${cfg.serviceName}.appID}";
      description = "PostgreSQL data directory";
    };
    
    enableTCPIP = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TCP/IP connections";
    };
  };

  config = mkIf cfg.enable {
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "postgres";
      group = "postgres";
    };

    services.postgresql = {
      enable = true;
      dataDir = cfg.dataDir;
      enableTCPIP = cfg.enableTCPIP;
    };
  };
}

