{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.wellknown;
  matrixCfg = config.modules.services.communication.matrix-synapse;
  pixelfedCfg = config.modules.services.communication.pixelfed;
  
  # Determine if this is the service host or an edge proxy
  isHostServer = config.networking.hostName == cfg.serviceHost;

  # Target host for proxying services
  targetHost = if isHostServer then "localhost" else cfg.serviceHost;
in
{
  options.modules.services.communication.wellknown = {
    enable = mkEnableOption "Well-known delegation for federation services";

    domain = mkOption {
      type = types.str;
      default = config.networking.domain;
      description = "Root domain for well-known endpoints";
    };

    serviceHost = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Hostname of the machine running Matrix and Pixelfed. Defaults to the current host (service and proxy on the same machine). Edge servers set this to the host running Matrix/Pixelfed.";
    };
  };

  config = mkIf cfg.enable {
    # Well-Known Delegation - Serve on base domain for federation discovery
    # Works for both host server (localhost routing) and edge servers (remote routing to host)
    # Note: On edge servers uses HTTPS with Cloudflare DNS-01, on host server uses HTTP (internal)
    modules.services.vHosts.hosts.${if isHostServer then "http://${cfg.domain}" else cfg.domain} = {
      rawConfig = true;
      public = !isHostServer;  # Public on edge servers for federation, internal on host server
      dnsChallenge = !isHostServer;
      displayName = "Well-Known";
      category = "infrastructure";
      monitor = false;
      extraConfig = ''
        # Matrix well-known endpoints - serve directly
        ${if matrixCfg.enable || !isHostServer then ''
        handle /.well-known/matrix/server {
          header Content-Type application/json
          header Access-Control-Allow-Origin *
          respond `{"m.server": "matrix.${cfg.domain}:443"}` 200
        }
        handle /.well-known/matrix/client {
          header Content-Type application/json
          header Access-Control-Allow-Origin *
          respond `{"m.homeserver":{"base_url":"https://matrix.${cfg.domain}"}}` 200
        }
        '' else ""}
        
        # Pixelfed ActivityPub/Federation endpoints
        ${if pixelfedCfg.enable || !isHostServer then ''
        handle /.well-known/webfinger* {
          reverse_proxy http://${targetHost}:8085
        }
        handle /.well-known/host-meta* {
          reverse_proxy http://${targetHost}:8085
        }
        handle /.well-known/nodeinfo* {
          reverse_proxy http://${targetHost}:8085
        }
        '' else ""}
        
        # Default handler - redirect to Pixelfed or 404
        handle {
          ${if pixelfedCfg.enable || !isHostServer then ''
          redir https://${pixelfedCfg.domain}{uri}
          '' else ''
          respond 404
          ''}
        }
      '';
    };
  };
}
