{ config, lib, ... }:

with lib;
let
  cfg = config.modules.services.productivity.actualHttpApi;
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
      default = 5007;
      description = "Container port for the Actual HTTP API (the app's own PORT default)";
    };

    image = mkOption {
      type = types.str;
      default = "jhonderson/actual-http-api:latest";
      description = "OCI image for the Actual HTTP API";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/actual-http-api";
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
      default = optional (config.age.secrets ? actual-http-api-secrets) config.age.secrets.actual-http-api-secrets.path;
      description = "Environment files passed to the Actual HTTP API container (must provide ACTUAL_SERVER_PASSWORD and API_KEY)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

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
      displayName = "Actual API";
      category = "productivity";
      monitor = false;
    };
  };
}
