{ config, lib, ... }:

with lib;

let
  cfg = config.modules.services.providers.appManifest;

  shortcutHosts = filter (h: h.enable && h.shortcut)
    (attrValues config.modules.services.vHosts.hosts);

  appsJson = builtins.toJSON {
    apps = map (h: {
      name     = h.displayName;
      url      = "https://${h.virtualHost}";
      category = if h.category != "" then h.category else "services";
      icon     = h.icon;
    }) shortcutHosts;
  };
in
{
  options.modules.services.providers.appManifest = {
    enable = mkEnableOption "App manifest JSON endpoint (consumed by desktop app-shortcuts)";

    domain = mkOption {
      type    = types.str;
      default = "apps-manifest.${config.networking.domain}";
      description = "Domain to serve the JSON manifest on.";
    };
  };

  config = mkIf cfg.enable {
    modules.services.vHosts.hosts.${cfg.domain} = {
      shortcut    = false;
      monitor     = false;
      dnsChallenge = false;
      rawConfig   = true;
      extraConfig = ''
        header Access-Control-Allow-Origin "*"
        header Content-Type "application/json; charset=utf-8"
        respond `${appsJson}` 200
      '';
    };
  };
}
