{ config, lib, ... }:

with lib;

let
  cfg = config.modules.services.providers.appManifest;

  shortcutHosts = filter (h: h.enable && h.shortcut)
    (attrValues config.modules.services.vHosts.hosts);

  # A virtualHost may carry an explicit scheme — Caddy treats a leading
  # "http://" as a site address that disables automatic HTTPS (the well-known
  # endpoint does this on the host server). Strip any scheme before rebuilding
  # the URL, otherwise the manifest emits "https://http://domain". Mirrors the
  # normalisation in providers/dns-technitium.nix.
  urlOf = vhost:
    if hasPrefix "http://" vhost
    then vhost
    else "https://${removePrefix "https://" vhost}";

  appsJson = builtins.toJSON {
    apps = map (h: {
      name     = h.displayName;
      url      = urlOf h.virtualHost;
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
      # dnsChallenge must stay true (the default). This domain is internal-only
      # — it is NXDOMAIN on public resolvers — so HTTP-01 and TLS-ALPN-01 can
      # never validate, and Caddy retries forever. DNS-01 only needs a TXT
      # record in the Cloudflare zone, which works without any public A record.
      rawConfig   = true;
      extraConfig = ''
        header Access-Control-Allow-Origin "*"
        header Content-Type "application/json; charset=utf-8"
        respond `${appsJson}` 200
      '';
    };
  };
}
