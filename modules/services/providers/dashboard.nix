{ config, lib, ... }:

# ── Dashboard provider (TBD) ─────────────────────────────────────────────────
#
# This module will auto-populate a self-hosted dashboard with every enabled
# vHost, using the registry metadata: displayName, category, icon, virtualHost.
#
# Candidates under evaluation:
#   - Homarr       — declarative NixOS module available in nixpkgs
#   - Homepage     — YAML-config-driven, widely used, nixpkgs module available
#   - Dasherr      — minimal, JSON config
#
# Once a tool is chosen, this stub becomes a full provider that:
#   1. Installs and starts the dashboard service
#   2. Generates service tiles from config.modules.services.vHosts.hosts
#      (filtered to h.enable entries, grouped by h.category)
#   3. Uses h.virtualHost as the launch URL and h.displayName as the label
#
# ─────────────────────────────────────────────────────────────────────────────

with lib;

let
  cfg = config.modules.services.providers.dashboard;

  dashboardHosts = filter (h: h.enable)
    (attrValues config.modules.services.vHosts.hosts);
in
{
  options.modules.services.providers.dashboard = {
    enable = mkEnableOption "Dashboard provider for vHosts (implementation TBD)";

    provider = mkOption {
      type = types.enum [ "homepage" "homarr" "dasherr" ];
      default = "homepage";
      description = "Which dashboard tool to configure.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port the dashboard service listens on.";
    };

    domain = mkOption {
      type = types.str;
      default = "home.${config.networking.domain}";
      description = "Domain to expose the dashboard on (registered as a vHost automatically).";
    };
  };

  config = mkIf cfg.enable {
    warnings = [
      "modules.services.providers.dashboard is enabled but not yet implemented (tool selection pending). Would render ${toString (builtins.length dashboardHosts)} service tiles."
    ];
  };
}
