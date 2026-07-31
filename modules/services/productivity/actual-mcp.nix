{ config, lib, ... }:

with lib;
let
  cfg = config.modules.services.productivity.actualMcp;
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
  options.modules.services.productivity.actualMcp = {
    enable = mkEnableOption "Actual Budget MCP Server";

    domain = mkOption {
      type = types.str;
      default = "mcp.budget.${config.networking.domain}";
      description = "Domain for the Actual MCP Server";
    };

    port = mkOption {
      type = types.port;
      default = 3600;
      description = "Host port for the Actual MCP Server";
    };

    containerPort = mkOption {
      type = types.port;
      default = 3600;
      description = "Container port for the Actual MCP Server";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/agigante80/actual-mcp-server:latest";
      description = "OCI image for the Actual MCP Server";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/actual-mcp";
      description = "Data directory for the Actual MCP Server container (local budget cache)";
    };

    logsDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/actual-mcp-logs";
      description = "Logs directory for the Actual MCP Server container";
    };

    actualServerUrl = mkOption {
      type = types.str;
      default = "";
      description = "Actual server URL (defaults to the configured Actual Budget service when empty)";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables for the Actual MCP Server container";
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = optional (config.age.secrets ? actual-mcp-secrets) config.age.secrets.actual-mcp-secrets.path;
      description = "Environment files passed to the Actual MCP Server container (must provide ACTUAL_PASSWORD, ACTUAL_BUDGET_SYNC_ID, MCP_SSE_AUTHORIZATION)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port (leave closed; reach the server through the reverse proxy)";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.logsDir} 0755 root root -"
    ];

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    virtualisation.oci-containers.containers."actual-mcp" = {
      image = cfg.image;
      cmd = [ "--http" ];
      environment = baseEnvironment;
      environmentFiles = cfg.environmentFiles;
      ports = [
        "${toString cfg.port}:${toString cfg.containerPort}/tcp"
      ];
      volumes = [
        "${cfg.dataDir}:/app/data:rw"
        "${cfg.logsDir}:/app/logs:rw"
      ];
      log-driver = "journald";
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Actual MCP";
      category = "productivity";
      monitor = false;
      public = false;
    };
  };
}
