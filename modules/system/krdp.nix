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
        # lego needs CF_DNS_API_TOKEN=<token>; the agenix secret is a raw value,
        # so krdp-acme-credentials formats it at runtime.
        environmentFile = "/run/krdp/acme-cf.env";
        group = "krdp-cert";
      };
    };

    users.groups.krdp-cert = {};
    users.users.${cfg.user}.extraGroups = [ "krdp-cert" ];

    # Write Cloudflare credentials in the KEY=VALUE format lego expects.
    # Runs before the ACME service; reads the raw token from agenix.
    systemd.services.krdp-acme-credentials = {
      description = "Prepare Cloudflare credentials for krdp ACME";
      before = [ "acme-${domain}.service" "acme-selfsigned-${domain}.service" ];
      requiredBy = [ "acme-${domain}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/krdp
        echo "CF_DNS_API_TOKEN=$(cat ${config.age.secrets.cloudflare-api-token.path})" \
          > /run/krdp/acme-cf.env
        chmod 600 /run/krdp/acme-cf.env
        chown acme:acme /run/krdp/acme-cf.env
      '';
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # krdpserver as a user service; --plasma avoids XDP portal path issues on KDE.
    systemd.user.services.krdp = {
      description = "KDE RDP Server";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.krdp}/bin/krdpserver --certificate ${certDir}/cert.pem --certificate-key ${certDir}/key.pem --plasma --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
