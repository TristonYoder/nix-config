{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.invoiceNinja;
in
{
  options.modules.services.productivity.invoiceNinja = {
    enable = mkEnableOption "Invoice Ninja - open-source invoicing and client management";

    domain = mkOption {
      type = types.str;
      default = "invoices.${config.networking.domain}";
      description = "Domain for Invoice Ninja";
    };

    port = mkOption {
      type = types.port;
      default = 8069;
      description = "Internal port for Invoice Ninja";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/invoice-ninja";
      description = "Data directory for Invoice Ninja public and storage volumes";
    };

    secretsFile = mkOption {
      type = types.path;
      default = config.age.secrets.invoice-ninja-env.path;
      description = ''
        Path to environment file containing secrets.
        Required variables: APP_KEY, DB_HOST, DB_DATABASE, DB_USERNAME, DB_PASSWORD.
        APP_URL is set automatically from the domain option.
        Create with: cd secrets && ./encrypt-secret.sh -n invoice-ninja-env.age -e
      '';
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."invoice-ninja" = {
      image = "invoiceninja/invoiceninja:5";
      environmentFiles = [ cfg.secretsFile ];
      environment = {
        APP_URL = "https://${cfg.domain}";
        REQUIRE_HTTPS = "true";
        APP_ENV = "production";
      };
      volumes = [
        "${cfg.dataDir}/public:/var/www/app/public:rw"
        "${cfg.dataDir}/storage:/var/www/app/storage:rw"
      ];
      ports = [
        "127.0.0.1:${toString cfg.port}:80/tcp"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=invoice-ninja"
        "--network=invoice-ninja_default"
      ];
    };

    systemd.services."docker-invoice-ninja" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-invoice-ninja_default.service" ];
      requires = [ "docker-network-invoice-ninja_default.service" ];
      partOf = [ "docker-compose-invoice-ninja-root.target" ];
      wantedBy = [ "docker-compose-invoice-ninja-root.target" ];
    };

    systemd.services."docker-network-invoice-ninja_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f invoice-ninja_default";
      };
      script = ''
        docker network inspect invoice-ninja_default || docker network create invoice-ninja_default
      '';
      partOf = [ "docker-compose-invoice-ninja-root.target" ];
      wantedBy = [ "docker-compose-invoice-ninja-root.target" ];
    };

    systemd.targets."docker-compose-invoice-ninja-root" = {
      unitConfig = {
        Description = "Invoice Ninja Docker services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Invoice Ninja";
      category = "productivity";
      icon = "invoice-ninja";
    };
  };
}
