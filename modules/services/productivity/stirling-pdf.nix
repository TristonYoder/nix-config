{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.stirlingPdf;
in
{
  options.modules.services.productivity.stirlingPdf = {
    enable = mkEnableOption "Stirling PDF self-hosted PDF manipulation tools";

    domain = mkOption {
      type = types.str;
      default = "pdf.${config.networking.domain}";
      description = "Domain for Stirling PDF";
    };

    port = mkOption {
      type = types.int;
      default = 7878;
      description = "Port for Stirling PDF to listen on";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers."stirling-pdf" = {
      image = "frooodle/s-pdf:latest";
      ports = [ "127.0.0.1:${toString cfg.port}:8080" ];
      volumes = [
        "/var/lib/stirling-pdf/data:/usr/share/tessdata"
        "/var/lib/stirling-pdf/configs:/configs"
      ];
      environment = {
        DOCKER_ENABLE_SECURITY = "false";
      };
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Stirling PDF";
      category = "productivity";
      icon = "stirling-pdf";
    };
  };
}
