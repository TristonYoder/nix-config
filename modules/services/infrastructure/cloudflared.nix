{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.cloudflared;
in
{
  options.modules.services.infrastructure.cloudflared = {
    enable = mkEnableOption "Cloudflare Tunnel";
    
    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Cloudflare tunnel token";
    };
  };

  config = mkIf cfg.enable {
    # Create cloudflared user and group
    users.users.cloudflared = {
      group = "cloudflared";
      isSystemUser = true;
    };
    users.groups.cloudflared = { };

    # Cloudflare Tunnel systemd service
    systemd.services.cloudflared_tunnel = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      script = ''
        TOKEN=$(cat ${cfg.tokenFile})
        exec ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token="$TOKEN"
      '';
      serviceConfig = {
        Restart = "always";
        User = "cloudflared";
        Group = "cloudflared";
      };
    };
  };
}

