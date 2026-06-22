{ config, lib, ... }:

# ── Monitoring provider (TBD) ────────────────────────────────────────────────
#
# This module will auto-configure a monitoring service for every vHost that has
# monitor = true (the default).  The implementation is pending tool selection.
#
# Candidates under evaluation:
#   - Gatus       — declarative YAML config, lightweight, Prometheus metrics
#   - Uptime Kuma — GUI-driven but has a REST API for declarative seeding
#
# Once a tool is chosen, this stub becomes a full provider that:
#   1. Installs and starts the monitoring service
#   2. Generates monitor targets from config.modules.services.vHosts.hosts
#      (filtering to hosts where h.enable && h.monitor)
#   3. Exposes an option set matching the provider's configuration surface
#
# ────────────────────────────────────────────────────────────────────────────

with lib;

let
  cfg = config.modules.services.providers.monitoring;

  monitoredHosts = filter (h: h.enable && h.monitor)
    (attrValues config.modules.services.vHosts.hosts);
in
{
  options.modules.services.providers.monitoring = {
    enable = mkEnableOption "Monitoring provider for vHosts (implementation TBD)";

    # Placeholder — will expand to provider-specific options once tool is chosen
    provider = mkOption {
      type = types.enum [ "gatus" "uptime-kuma" ];
      default = "gatus";
      description = "Which monitoring tool to configure.";
    };
  };

  config = mkIf cfg.enable {
    warnings = [
      "modules.services.providers.monitoring is enabled but not yet implemented (tool selection pending). Monitoring targets: ${toString (map (h: h.virtualHost) monitoredHosts)}"
    ];
  };
}
