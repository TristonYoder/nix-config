{ config, lib, ... }:

with lib;
let
  cfg = config.modules.services.productivity.actualHttpApi;
  helpers = import ../../lib.nix { inherit lib; };
  actualModule = config.modules.services.productivity.actual;
  resolvedActualServerUrl =
    if cfg.actualServerUrl != "" then
      cfg.actualServerUrl
    else
      "http://host.containers.internal:${toString actualModule.port}";
  baseEnvironment = cfg.environment
    // optionalAttrs (resolvedActualServerUrl != "") {
      ACTUAL_SERVER_URL = resolvedActualServerUrl;
    }
    // {
      TZ = config.time.timeZone;
    };
in
{
  options.modules.services.productivity.actualHttpApi = {
    enable = mkEnableOption "Actual Budget HTTP API";

    serviceName = mkOption {
      type = types.str;
      default = "Actual Budget API";
      description = "Service name used for appData registration";
    };

    domain = mkOption {
      type = types.str;
      default = "api.budget.theyoder.family";
      description = "Domain for the Actual HTTP API";
    };

    port = mkOption {
      type = types.port;
      default = 5007;
      description = "Host port for the Actual HTTP API";
    };

    containerPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Container port for the Actual HTTP API";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/jhonderson/actual-http-api:latest";
      description = "OCI image for the Actual HTTP API";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${config.modules.services.appData.mount}/${config.modules.services.appData.services.${cfg.serviceName}.appID}";
      description = "Data directory for the Actual HTTP API container";
    };

    actualServerUrl = mkOption {
      type = types.str;
      default = "";
      description = "Actual server URL (defaults to the configured Actual Budget service when empty)";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables for the Actual HTTP API container";
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "Environment files passed to the Actual HTTP API container";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port";
    };
  };

  config = mkIf cfg.enable {
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "root";
      group = "root";
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    virtualisation.oci-containers.containers."actual-http-api" = {
      image = cfg.image;
      environment = baseEnvironment;
      environmentFiles = cfg.environmentFiles;
      ports = [
        "${toString cfg.port}:${toString cfg.containerPort}/tcp"
      ];
      volumes = [
        "${cfg.dataDir}:/data:rw"
      ];
      log-driver = "journald";
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
