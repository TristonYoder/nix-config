{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.pocket-id;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  options.modules.services.infrastructure.pocket-id = {
    enable = mkEnableOption "Pocket ID authentication service";

    domain = mkOption {
      type = types.str;
      default = "id.theyoder.family";
      description = "Domain for Pocket ID";
    };

    port = mkOption {
      type = types.port;
      default = 3002;
      description = "Pocket ID port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/pocket-id";
      description = "Data directory for Pocket ID";
    };

    encryptionKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing ENCRYPTION_KEY (must be at least 16 bytes)";
    };

    trustProxy = mkOption {
      type = types.bool;
      default = true;
      description = "Trust proxy headers for Pocket ID";
    };

    analyticsDisabled = mkOption {
      type = types.bool;
      default = true;
      description = "Disable analytics in Pocket ID";
    };
  };

  config = mkIf cfg.enable {
    # Disable the broken nixpkgs pocket-id service
    systemd.services.pocket-id-backend.enable = false;
    systemd.services.pocket-id-frontend.enable = false;

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 pocket-id pocket-id - -"
    ];

    # Create pocket-id user and group
    users.users.pocket-id = {
      isSystemUser = true;
      group = "pocket-id";
      home = cfg.dataDir;
      createHome = true;
      shell = "${pkgs.shadow}/sbin/nologin";
    };

    users.groups.pocket-id = { };

    # Generate encryption key if not provided
    systemd.services.pocket-id-init = mkIf (cfg.encryptionKeyFile == null) {
      description = "Initialize Pocket ID encryption key";
      wantedBy = [ "multi-user.target" ];
      before = [ "pocket-id.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "pocket-id";
        Group = "pocket-id";
      };
      
      script = ''
        if [ ! -f ${cfg.dataDir}/.encryption_key ]; then
          ${pkgs.openssl}/bin/openssl rand -base64 16 > ${cfg.dataDir}/.encryption_key
          chmod 600 ${cfg.dataDir}/.encryption_key
        fi
      '';
    };

    # Main Pocket ID service
    systemd.services.pocket-id = {
      description = "Pocket ID authentication service";
      after = [ "network-online.target" ] ++ lib.optionals (cfg.encryptionKeyFile == null) [ "pocket-id-init.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "pocket-id";
        Group = "pocket-id";
        Restart = "always";
        RestartSec = "10";
        StartLimitIntervalSec = "60";
        StartLimitBurst = "3";
        
        # Read only root filesystem with /run and /tmp writable
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        
        # Security hardening
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX";
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        PrivateDevices = true;
        DevicePolicy = "closed";
        RemoveIPC = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
      };

      environment = {
        "APP_URL" = "https://${cfg.domain}";
        "PORT" = toString cfg.port;
        "TRUST_PROXY" = lib.boolToString cfg.trustProxy;
        "ANALYTICS_DISABLED" = lib.boolToString cfg.analyticsDisabled;
        "PUBLIC_APP_URL" = "http://localhost";
        "NODE_ENV" = "production";
      };

      script = let
        encryptionKeyPath = if cfg.encryptionKeyFile != null then cfg.encryptionKeyFile else "${cfg.dataDir}/.encryption_key";
      in ''
        export ENCRYPTION_KEY="$(cat ${encryptionKeyPath})"
        exec ${pkgs-unstable.pocket-id}/bin/pocket-id
      '';
    };

    # Caddy reverse proxy
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port} {
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
        }

        import cloudflare_tls
      '';
    };
  };
}
