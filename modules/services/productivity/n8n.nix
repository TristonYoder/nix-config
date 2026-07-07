{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.productivity.n8n;
  # Get unstable packages with unfree allowed
  unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config = {
      allowUnfree = true;
    };
  };
in
{
  options.modules.services.productivity.n8n = {
    enable = mkEnableOption "n8n workflow automation";
    
    domain = mkOption {
      type = types.str;
      default = "n8n.${config.networking.domain}";
      description = "Domain for n8n";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port for n8n";
    };
  };

  config = mkIf cfg.enable {
    # Use n8n from unstable via overlay
    nixpkgs.overlays = [
      (final: prev: {
        n8n = unstable.n8n;
      })
    ];

    # n8n service
    services.n8n = {
      enable = true;
      openFirewall = cfg.openFirewall;
      environment.WEBHOOK_URL = "https://${cfg.domain}";
    };

    # Community node installs shell out to `npm install`, which in turn
    # spawns `tar` to unpack the downloaded package. The systemd unit's PATH
    # otherwise has neither, causing "spawn npm ENOENT" then "spawn tar ENOENT".
    # Use nodejs from the same channel as n8n itself to avoid a node/npm
    # version mismatch against n8n's bundled node_modules.
    systemd.services.n8n.path = [ unstable.nodejs pkgs.gnutar ];

    # Caddy virtual host
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = 5678;
      displayName = "n8n";
      category = "productivity";
      icon = "n8n";
    };
  };
}
