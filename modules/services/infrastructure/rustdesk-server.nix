{ config, lib, pkgs, ... }:

# Self-hosted RustDesk ID/rendezvous (hbbs) and relay (hbbr) server.
#
# Clients are pointed at it by home/modules/rustdesk.nix. The server's public
# key is generated on first start at /var/lib/private/rustdesk/id_ed25519.pub
# (DynamicUser state dir). It is not secret; copy it into
# home/modules/rustdesk.nix's `key` default, then set `enforceKey = true` here
# so clients without the key are refused.

with lib;
let
  cfg = config.modules.services.infrastructure.rustdesk-server;
in
{
  options.modules.services.infrastructure.rustdesk-server = {
    enable = mkEnableOption "RustDesk server (hbbs + hbbr)";

    domain = mkOption {
      type = types.str;
      default = "remote.${config.networking.domain}";
      description = "DNS name clients use to reach the ID and relay servers.";
    };

    aliases = mkOption {
      type = types.listOf types.str;
      default = [ "rustdesk.${config.networking.domain}" ];
      description = "Extra DNS names that resolve to the same server.";
    };

    ipAddress = mkOption {
      type = types.str;
      default = "10.150.100.30";
      description = ''
        Address the DNS name resolves to. RustDesk is not HTTP, so the vHost is
        DNS-only (A record) rather than proxied through Caddy.
      '';
    };

    enforceKey = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Pass `-k _` to hbbs/hbbr so only clients configured with this server's
        public key can use it. Enable once the key is set on the clients.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open TCP 21115-21119 and UDP 21116.";
    };
  };

  config = mkIf cfg.enable {
    services.rustdesk-server = {
      enable = true;
      openFirewall = cfg.openFirewall;
      signal.relayHosts = [ cfg.domain ];
      signal.extraArgs = optionals cfg.enforceKey [ "-k" "_" ];
      relay.extraArgs = optionals cfg.enforceKey [ "-k" "_" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      ipAddress = cfg.ipAddress;
      serverAliases = cfg.aliases;
      displayName = "RustDesk";
      category = "infrastructure";
      icon = "rustdesk";
      monitor = false;
      dashboard = false;
      shortcut = false;
    };
  };
}
