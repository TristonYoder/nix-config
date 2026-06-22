{ config, lib, ... }:

with lib;

let
  cfg = config.modules.services.providers.dashboard-homepage;

  dashboardHosts = filter (h: h.enable)
    (attrValues config.modules.services.vHosts.hosts);

  # Group vHosts by category, falling back to "Services" for uncategorized
  groupByCategory = hosts:
    let
      grouped = groupBy (h: if h.category != "" then h.category else "Services") hosts;
      titleCase = s:
        let first = lib.toUpper (lib.substring 0 1 s);
            rest  = lib.substring 1 (lib.stringLength s - 1) s;
        in "${first}${rest}";
      toGroupEntry = cat: members:
        { "${titleCase cat}" = map (h:
            { "${h.displayName}" = {
                href = "https://${h.virtualHost}";
              } // optionalAttrs (h.icon != "") { icon = h.icon; };
            }) members;
        };
    in mapAttrsToList toGroupEntry grouped;

  homepageServices = groupByCategory dashboardHosts;
in
{
  options.modules.services.providers.dashboard-homepage = {
    enable = mkEnableOption "Homepage dashboard provider (static, per-host, build-time generated)";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port Homepage listens on.";
    };

    domain = mkOption {
      type = types.str;
      default = "home.${config.networking.domain}";
      description = "Domain to expose Homepage on (registered as a vHost automatically).";
    };

    title = mkOption {
      type = types.str;
      default = config.networking.domain;
      description = "Browser title shown in Homepage.";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra Homepage settings (widgets, bookmarks, settings block, etc.).";
      example = literalExpression ''
        {
          widgets = [
            { resources = { cpu = true; memory = true; disk = "/"; }; }
            { search = { provider = "google"; target = "_blank"; }; }
          ];
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;
      allowedHosts = "${cfg.domain},localhost:${toString cfg.port}";
      services = homepageServices;
    } // cfg.extraSettings;

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Home";
      category = "infrastructure";
      monitor = false;
    };
  };
}
