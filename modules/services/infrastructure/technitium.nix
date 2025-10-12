{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.technitium;
in
{
  options.modules.services.infrastructure.technitium = {
    enable = mkEnableOption "Technitium DNS Server";
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for DNS server";
    };
  };

  config = mkIf cfg.enable {
    services.technitium-dns-server = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };
  };
}

