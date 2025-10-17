{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.wellknown;
  matrixCfg = config.modules.services.communication.matrix-synapse;
  pixelfedCfg = config.modules.services.communication.pixelfed;
  
  # Determine if this is the host server (david) or edge server (PITS)
  isHostServer = config.networking.hostName == "david";
  
  # Target host for proxying services - localhost for host server, david hostname for edge servers
  targetHost = if isHostServer then "localhost" else "david";
in
{
  options.modules.services.communication.wellknown = {
    enable = mkEnableOption "Well-known delegation for federation services";
    
    domain = mkOption {
      type = types.str;
      default = "theyoder.family";
      description = "Root domain for well-known endpoints";
    };
  };

  config = mkIf cfg.enable {
    # Well-Known Delegation - Serve on base domain for federation discovery
    # Works for both host server (localhost routing) and edge servers (remote routing to host)
    # Note: On edge servers uses HTTPS with HTTP-01 challenge, on host server uses HTTP (internal)
    services.caddy.virtualHosts.${if isHostServer then "http://${cfg.domain}" else cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
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
          redir https://pixelfed.${cfg.domain}{uri}
          '' else ''
          respond 404
          ''}
        }
        
        ${if !isHostServer then "# No TLS config - let Caddy use default HTTP-01 challenge" else ""}
      '';
    };
  };
}

