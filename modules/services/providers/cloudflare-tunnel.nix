{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.providers.cloudflare-tunnel;

  # vHosts that are public and enabled
  publicHosts = filter (h: h.enable && h.public)
    (attrValues config.modules.services.vHosts.hosts);

  # Build upstream target for a host (mirrors Caddy's logic)
  upstreamOf = h:
    if h.reverseProxyAddress != null
    then h.reverseProxyAddress
    else "${if h.reverseProxySSL then "https" else "http"}://${h.reverseProxyHost}:${toString h.reverseProxyPort}";

  # Cloudflared ingress rules — one per public vHost, plus the catch-all
  ingressRules = (map (h: {
    hostname = h.virtualHost;
    service  = upstreamOf h;
  }) publicHosts) ++ [{ service = "http_status:404"; }];
in
{
  options.modules.services.providers.cloudflare-tunnel = {
    enable = mkEnableOption "Cloudflare Tunnel provider for public vHosts";

    tunnelId = mkOption {
      type = types.str;
      description = "Cloudflare Tunnel UUID (from `cloudflared tunnel create`).";
    };

    tunnelSecretFile = mkOption {
      type = types.path;
      default = config.age.secrets.cloudflare-tunnel-secret.path;
      description = "Path to the tunnel credentials JSON file (agenix secret).";
    };

    tunnelName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Tunnel name (informational, matches what was created in Cloudflare).";
    };

    # When Caddy is the local reverse proxy, tunnel to it over HTTP.
    # Override if you want cloudflared to bypass Caddy and hit upstreams directly.
    localProxyPort = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = ''
        If set, ALL public vHosts are tunneled to http://localhost:''${localProxyPort}
        (i.e. through local Caddy) rather than each service's upstream directly.
        Leave null to route each vHost directly to its upstream.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = publicHosts != [ ];
      message = "cloudflare-tunnel provider is enabled but no vHosts have public = true.";
    }];

    services.cloudflared = {
      enable = true;
      tunnels.${cfg.tunnelName} = {
        credentialsFile = cfg.tunnelSecretFile;
        default = "http_status:404";
        ingress =
          if cfg.localProxyPort != null
          then
            # Route everything through local Caddy — simplest setup
            listToAttrs (map (h: nameValuePair h.virtualHost
              "http://localhost:${toString cfg.localProxyPort}") publicHosts)
          else
            # Route each host directly to its upstream
            listToAttrs (map (h: nameValuePair h.virtualHost (upstreamOf h)) publicHosts);
      };
    };
  };
}
