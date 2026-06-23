{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.providers.monitoring;

  monitoredHosts = filter (h: h.enable && h.monitor)
    (attrValues config.modules.services.vHosts.hosts);

  # Generate a Gatus endpoint for each monitored vHost
  gatuEndpoints = map (h: {
    name     = h.displayName;
    url      = "https://${h.virtualHost}";
    interval = cfg.interval;
    conditions = [
      "[STATUS] < 500"
    ] ++ optionals cfg.checkTLS [
      "[CERTIFICATE_EXPIRATION] > 72h"
    ];
  }) monitoredHosts;

  # /etc/hosts entries so Gatus resolves internal vHost domains to localhost
  # (Caddy listens on 0.0.0.0:443 with per-domain TLS, so this works for all)
  extraHostsEntries = concatMapStrings (h: "127.0.0.1 ${h.virtualHost}\n") monitoredHosts;
in
{
  options.modules.services.providers.monitoring = {
    enable = mkEnableOption "Gatus monitoring provider for vHosts";

    port = mkOption {
      type = types.port;
      default = 8090;
      description = "Port Gatus listens on.";
    };

    domain = mkOption {
      type = types.str;
      default = "status.${config.networking.domain}";
      description = "Domain to expose Gatus on (registered as a vHost automatically).";
    };

    interval = mkOption {
      type = types.str;
      default = "5m";
      description = "Default check interval (Gatus duration string, e.g. \"1m\", \"5m\").";
    };

    checkTLS = mkOption {
      type = types.bool;
      default = true;
      description = "Also verify TLS certificate expiry (>72h) on each endpoint.";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra settings merged into the Gatus config (freeform, see upstream docs).";
    };
  };

  config = mkIf cfg.enable {
    networking.extraHosts = extraHostsEntries;

    services.gatus = {
      enable = true;
      settings = mkMerge [
        {
          web.port = cfg.port;
          endpoints = gatuEndpoints;
        }
        cfg.extraSettings
      ];
    };

    # Auto-register the status page in the vHosts registry
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Status";
      category = "infrastructure";
      monitor = false; # don't monitor the monitor
    };
  };
}
