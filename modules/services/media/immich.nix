{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.immich;
in
{
  options.modules.services.media.immich = {
    enable = mkEnableOption "Immich photo management";
    
    domain = mkOption {
      type = types.str;
      default = "photos.${config.networking.domain}";
      description = "Primary domain for Immich";
    };
    
    publicProxyDomain = mkOption {
      type = types.str;
      default = "share.photos.${config.networking.domain}";
      description = "Domain for public sharing proxy";
    };
    
    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Immich server port";
    };
    
    publicProxyPort = mkOption {
      type = types.port;
      default = 2284;
      description = "Immich public proxy port";
    };
    
    mediaLocation = mkOption {
      type = types.str;
      default = "/data/docker-appdata/immich/media";
      description = "Location for media files";
    };

    oauth = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "OAuth login";

          issuerUrl = mkOption {
            type = types.str;
            default = "";
            description = "OAuth issuer URL (OIDC endpoint)";
          };

          clientId = mkOption {
            type = types.str;
            default = "";
            description = "OAuth client ID";
          };

          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing OAuth client secret (encrypted with agenix)";
          };

          autoRegister = mkOption {
            type = types.bool;
            default = true;
            description = "Automatically register new OAuth users";
          };

          autoLaunch = mkOption {
            type = types.bool;
            default = false;
            description = "Automatically launch OAuth login";
          };

          buttonText = mkOption {
            type = types.str;
            default = "Login with OAuth";
            description = "Text displayed on OAuth login button";
          };

          scope = mkOption {
            type = types.str;
            default = "openid email profile";
            description = "OAuth scopes to request";
          };

          signingAlgorithm = mkOption {
            type = types.str;
            default = "RS256";
            description = "JWT signing algorithm";
          };

          profileSigningAlgorithm = mkOption {
            type = types.str;
            default = "none";
            description = "Profile signing algorithm";
          };

          tokenEndpointAuthMethod = mkOption {
            type = types.str;
            default = "client_secret_post";
            description = "Token endpoint authentication method";
          };

          roleClaim = mkOption {
            type = types.str;
            default = "immich_role";
            description = "OAuth claim for user role";
          };

          storageLabelClaim = mkOption {
            type = types.str;
            default = "preferred_username";
            description = "OAuth claim for storage label";
          };

          storageQuotaClaim = mkOption {
            type = types.str;
            default = "immich_quota";
            description = "OAuth claim for storage quota";
          };

          defaultStorageQuota = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Default storage quota for OAuth users (bytes)";
          };

          mobileOverrideEnabled = mkOption {
            type = types.bool;
            default = false;
            description = "Enable mobile OAuth override";
          };

          mobileRedirectUri = mkOption {
            type = types.str;
            default = "";
            description = "Mobile redirect URI";
          };

          timeout = mkOption {
            type = types.int;
            default = 30000;
            description = "OAuth timeout (milliseconds)";
          };
        };
      };
      default = {};
      description = "OAuth configuration";
    };
  };

  config = mkIf cfg.enable {
    # Immich service
    services.immich = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
      host = "0.0.0.0";
      mediaLocation = cfg.mediaLocation;
      settings.server.externalDomain = "https://${cfg.domain}";
      settings.oauth = {
        enabled = cfg.oauth.enable;
        issuerUrl = cfg.oauth.issuerUrl;
        clientId = cfg.oauth.clientId;
        clientSecret = optionalString (cfg.oauth.clientSecretFile != null) 
          (builtins.readFile cfg.oauth.clientSecretFile);
        autoRegister = cfg.oauth.autoRegister;
        autoLaunch = cfg.oauth.autoLaunch;
        buttonText = cfg.oauth.buttonText;
        scope = cfg.oauth.scope;
        signingAlgorithm = cfg.oauth.signingAlgorithm;
        profileSigningAlgorithm = cfg.oauth.profileSigningAlgorithm;
        tokenEndpointAuthMethod = cfg.oauth.tokenEndpointAuthMethod;
        roleClaim = cfg.oauth.roleClaim;
        storageLabelClaim = cfg.oauth.storageLabelClaim;
        storageQuotaClaim = cfg.oauth.storageQuotaClaim;
        defaultStorageQuota = cfg.oauth.defaultStorageQuota;
        mobileOverrideEnabled = cfg.oauth.mobileOverrideEnabled;
        mobileRedirectUri = cfg.oauth.mobileRedirectUri;
        timeout = cfg.oauth.timeout;
      };
    };

    # Immich Public Proxy for sharing
    services.immich-public-proxy = {
      enable = true;
      immichUrl = "http://localhost:${toString cfg.port}/";
      openFirewall = true;
      port = cfg.publicProxyPort;
    };

    # Caddy virtual hosts
    modules.services.vHosts.hosts.${cfg.domain} = {
      managedProxy = false;
      extraConfig = ''
        handle_path /share* {
          reverse_proxy http://localhost:${toString cfg.publicProxyPort}
        }
        handle {
          reverse_proxy http://localhost:${toString cfg.port}
        }
      '';
    };

    modules.services.vHosts.hosts.${cfg.publicProxyDomain} = {
      managedProxy = false;
      public = true;  # Public proxy for sharing photos externally
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.publicProxyPort}
      '';
    };
  };
}
