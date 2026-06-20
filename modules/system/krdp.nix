{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.krdp;
  domain = cfg.domain;
  certDir = "/var/lib/acme/${domain}";
in
{
  options.modules.system.krdp = {
    enable = mkEnableOption "KDE RDP server";

    domain = mkOption {
      type = types.str;
      default = "${config.networking.hostName}.theyoder.family";
      description = "Domain for TLS certificate via ACME DNS-01.";
    };

    port = mkOption {
      type = types.port;
      default = 3389;
    };

    user = mkOption {
      type = types.str;
      default = "tristonyoder";
      description = "User that krdpserver runs as; must be a Plasma session user.";
    };
  };

  config = mkIf cfg.enable {
    # ACME cert via Cloudflare DNS-01
    security.acme = {
      acceptTerms = true;
      defaults.email = "triston@7andco.studio";
      certs.${domain} = {
        dnsProvider = "cloudflare";
        # credentialFiles sets CF_DNS_API_TOKEN from the file contents directly
        # (no KEY= prefix needed — lego reads the raw value).
        credentialFiles = { CF_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-api-token.path; };
        group = "krdp-cert";
      };
    };

    users.groups.krdp-cert = {};
    users.users.${cfg.user}.extraGroups = [ "krdp-cert" ];

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # krdpserver as a user service; --plasma avoids XDP portal path issues on KDE.
    systemd.user.services.krdp = {
      description = "KDE RDP Server";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.kdePackages.krdp}/bin/krdpserver --certificate ${certDir}/cert.pem --certificate-key ${certDir}/key.pem --plasma --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
