{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.navidrome;
  hasOidc = cfg.oidc.enable && cfg.oidc.clientSecretFile != null;
in
{
  options.modules.services.media.navidrome = {
    enable = mkEnableOption "Navidrome music streaming server";

    domain = mkOption {
      type = types.str;
      default = "navidrome.${config.networking.domain}";
      description = "Domain for Navidrome";
    };

    port = mkOption {
      type = types.port;
      default = 4533;
      description = "Navidrome HTTP port";
    };

    musicDir = mkOption {
      type = types.str;
      default =
        if config.modules.services.media.jellyfin.enable
        then "${config.modules.services.media.jellyfin.mediaDir}/Music"
        else "/data/media/Music";
      description = "Path to the music library";
    };

    oidc = {
      enable = mkEnableOption "OIDC/SSO authentication via Pocket ID";

      discoveryUrl = mkOption {
        type = types.str;
        default = "https://id.theyoder.family/.well-known/openid-configuration";
        description = "OIDC provider discovery URL";
      };

      clientId = mkOption {
        type = types.str;
        default = "";
        description = "OIDC client ID from Pocket ID";
      };

      clientSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to agenix secret containing the OIDC client secret";
      };

      autoProvision = mkOption {
        type = types.bool;
        default = true;
        description = "Auto-create Navidrome accounts for new OIDC users";
      };

      loginButton = mkOption {
        type = types.str;
        default = "Login with SSO";
        description = "Label shown on the OIDC login button";
      };
    };
  };

  config = mkIf cfg.enable {
    services.navidrome = {
      enable = true;
      settings = {
        MusicFolder = cfg.musicDir;
        Port = cfg.port;
        Address = "0.0.0.0";
      } // optionalAttrs cfg.oidc.enable {
        OIDC = {
          Enabled = true;
          ClientID = cfg.oidc.clientId;
          DiscoveryURL = cfg.oidc.discoveryUrl;
          AutoProvision = cfg.oidc.autoProvision;
          LoginButton = cfg.oidc.loginButton;
          # ClientSecret is injected via environmentFile at runtime
        };
      };
      environmentFile = mkIf hasOidc "/run/navidrome-env/navidrome.env";
    };

    # Write OIDC client secret to an env file before navidrome starts.
    # EnvironmentFile is processed before ExecStart, so a separate oneshot service
    # is needed to generate the file in time.
    systemd.services.navidrome-env = mkIf hasOidc {
      description = "Generate Navidrome OIDC environment file";
      wantedBy = [ "navidrome.service" ];
      before = [ "navidrome.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = let
          script = pkgs.writeShellScript "navidrome-gen-env" ''
            install -d -m 700 -o navidrome -g navidrome /run/navidrome-env
            printf 'ND_OIDC_CLIENTSECRET=%s\n' "$(cat ${cfg.oidc.clientSecretFile})" \
              > /run/navidrome-env/navidrome.env
            chown navidrome:navidrome /run/navidrome-env/navidrome.env
            chmod 400 /run/navidrome-env/navidrome.env
          '';
        in "+${script}";
      };
    };

    users.users.navidrome.extraGroups = [ "media" ];

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
