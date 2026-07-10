{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.gitlab;

  # Falls back to the matching agenix secret (registered in modules/secrets.nix,
  # gated on modules.services.development.gitlab.enable) when no override path
  # is given. Never builtins.readFile these — GitLab wants a *path*, not the
  # decrypted contents, so the secret never touches the Nix store.
  secretPath = name: fileOpt:
    if fileOpt != null then fileOpt else config.age.secrets.${name}.path;
in
{
  options.modules.services.development.gitlab = {
    enable = mkEnableOption "GitLab self-hosted git service";

    domain = mkOption {
      type = types.str;
      default = "git.7co.dev";
      description = "Public domain GitLab is served on.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/gitlab";
      description = "GitLab state directory: repositories, uploads, config, logs.";
    };

    initialRootEmail = mkOption {
      type = types.str;
      default = "admin@${cfg.domain}";
      description = "Email address for the initial root account (first install only).";
    };

    rootPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a file containing the initial root account password
        (first install only). Defaults to agenix secret gitlab-root-password.
      '';
    };

    databasePasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a file containing the GitLab PostgreSQL user password.
        Defaults to agenix secret gitlab-db-password.
      '';
    };

    # ── Encryption secrets ────────────────────────────────────────────────
    # GitLab uses these to encrypt data at rest (DB columns, 2FA, sessions).
    # Generate once, keep forever: losing any of these locks users out of
    # 2FA or session state, or makes encrypted DB columns unreadable.
    secretKeyBaseFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file with the Rails secret_key_base (32+ random chars). Defaults to agenix secret gitlab-secret-key-base.";
    };

    otpSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file with the 2FA/OTP encryption secret (32+ random chars). Defaults to agenix secret gitlab-otp-secret.";
    };

    dbSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file with the DB attribute-encryption secret (32+ random chars). Defaults to agenix secret gitlab-db-secret.";
    };

    jwsSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to file with an RSA private key in PEM format (session JWT
        signing), e.g. generated with `openssl genrsa 2048`.
        Defaults to agenix secret gitlab-jws-key.
      '';
    };

    activeRecordPrimaryKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file with the ActiveRecord primary encryption key. Defaults to agenix secret gitlab-active-record-primary-key.";
    };

    activeRecordDeterministicKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file with the ActiveRecord deterministic encryption key (must differ from the primary key). Defaults to agenix secret gitlab-active-record-deterministic-key.";
    };

    activeRecordSaltFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file with the ActiveRecord encryption salt. Defaults to agenix secret gitlab-active-record-salt.";
    };

    # ── SMTP ────────────────────────────────────────────────────────────
    smtp = {
      enable = mkEnableOption "outbound email via SMTP";

      address = mkOption {
        type = types.str;
        default = "localhost";
        description = "SMTP server hostname.";
      };

      port = mkOption {
        type = types.port;
        default = 587;
        description = "SMTP server port.";
      };

      username = mkOption {
        type = types.str;
        default = "";
        description = "SMTP username.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file with the SMTP password. Defaults to agenix secret gitlab-smtp-password.";
      };

      fromAddress = mkOption {
        type = types.str;
        default = "gitlab@${cfg.domain}";
        description = "From address for outbound mail.";
      };

      displayName = mkOption {
        type = types.str;
        default = "GitLab";
        description = "Display name for outbound mail.";
      };
    };

    # ── Container registry ───────────────────────────────────────────────
    registry = {
      enable = mkEnableOption "GitLab container registry";

      domain = mkOption {
        type = types.str;
        default = "registry.${cfg.domain}";
        description = "Domain the container registry is served on.";
      };

      port = mkOption {
        type = types.port;
        default = 4567;
        description = "Internal port the registry daemon listens on.";
      };
    };

    # ── OIDC login (Pocket ID) ────────────────────────────────────────────
    # See docker/productivity/pocket-id.nix — the shared Pocket ID instance
    # at id.theyoder.family. Adds "Sign in with Pocket ID" as an extra option
    # on the login page; local GitLab accounts keep working alongside it.
    oidc = {
      enable = mkEnableOption "OIDC login via Pocket ID";

      issuerUrl = mkOption {
        type = types.str;
        default = "https://id.theyoder.family";
        description = "OIDC issuer URL.";
      };

      label = mkOption {
        type = types.str;
        default = "Pocket ID";
        description = "Label shown on the login button.";
      };

      clientId = mkOption {
        type = types.str;
        default = "";
        description = "OIDC client ID registered with the issuer.";
      };

      clientSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file with the OIDC client secret. Defaults to agenix secret gitlab-oidc-secret.";
      };

      autoLinkExistingUser = mkOption {
        type = types.bool;
        default = true;
        description = "Link OIDC sign-ins to an existing local account with a matching email instead of erroring.";
      };
    };

    # ── Backups ───────────────────────────────────────────────────────────
    backup = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable nightly gitlab-backup runs.";
      };

      startAt = mkOption {
        type = types.str;
        default = "*-*-* 02:00:00";
        description = "systemd calendar spec for the backup timer.";
      };

      keepTime = mkOption {
        type = types.int;
        default = 24 * 14; # 14 days, in hours
        description = "How long to keep backups, in hours. 0 means keep forever.";
      };
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Extra attributes merged into services.gitlab.extraConfig (the
        `production` block of config/gitlab.yml). Use the `_secret` convention
        for anything sensitive — see the services.gitlab.extraConfig option doc.
      '';
    };
  };

  config = mkIf cfg.enable {
    # GitLab Runner (CI) is a separate concern: register runners via
    # services.gitlab-runner once this instance is up, per-runner, with
    # tokens generated from the GitLab UI/API. Not wired here.

    services.gitlab = {
      enable = true;
      statePath = cfg.stateDir;

      host = cfg.domain;
      https = true;
      port = 443;

      initialRootEmail = cfg.initialRootEmail;
      initialRootPasswordFile = secretPath "gitlab-root-password" cfg.rootPasswordFile;

      databaseCreateLocally = true;
      databasePasswordFile = secretPath "gitlab-db-password" cfg.databasePasswordFile;

      secrets = {
        secretFile = secretPath "gitlab-secret-key-base" cfg.secretKeyBaseFile;
        otpFile = secretPath "gitlab-otp-secret" cfg.otpSecretFile;
        dbFile = secretPath "gitlab-db-secret" cfg.dbSecretFile;
        jwsFile = secretPath "gitlab-jws-key" cfg.jwsSecretFile;
        activeRecordPrimaryKeyFile = secretPath "gitlab-active-record-primary-key" cfg.activeRecordPrimaryKeyFile;
        activeRecordDeterministicKeyFile = secretPath "gitlab-active-record-deterministic-key" cfg.activeRecordDeterministicKeyFile;
        activeRecordSaltFile = secretPath "gitlab-active-record-salt" cfg.activeRecordSaltFile;
      };

      smtp = mkIf cfg.smtp.enable {
        enable = true;
        address = cfg.smtp.address;
        port = cfg.smtp.port;
        username = cfg.smtp.username;
        passwordFile = secretPath "gitlab-smtp-password" cfg.smtp.passwordFile;
        authentication = "login";
        enableStartTLSAuto = true;
      };

      registry = mkIf cfg.registry.enable {
        enable = true;
        host = cfg.registry.domain;
        port = cfg.registry.port;
        externalAddress = cfg.registry.domain;
        externalPort = 443;
        # Self-signed by gitlab-registry-cert.service on first activation
        # (auth cert, not TLS — Caddy terminates external TLS separately).
        certFile = "${cfg.stateDir}/registry/registry-auth.crt";
        keyFile = "${cfg.stateDir}/registry/registry-auth.key";
      };

      backup = {
        startAt = mkIf cfg.backup.enable [ cfg.backup.startAt ];
        keepTime = cfg.backup.keepTime;
      };

      # NOTE: extraConfig is a free-form YAML value, not a submodule option
      # tree — mkIf is only auto-resolved when assigned directly to a real
      # option, so conditionals here must use optionalAttrs/`//` instead.
      extraConfig = recursiveUpdate ({
        gitlab = {
          email_from = cfg.smtp.fromAddress;
          email_display_name = cfg.smtp.displayName;
          email_reply_to = cfg.smtp.fromAddress;
        };
      } // optionalAttrs cfg.oidc.enable {
        omniauth = {
          enabled = true;
          allow_single_sign_on = [ "openid_connect" ];
          block_auto_created_users = false;
          providers = [
            {
              name = "openid_connect";
              label = cfg.oidc.label;
              args = {
                name = "openid_connect";
                scope = [ "openid" "profile" "email" ];
                response_type = "code";
                issuer = cfg.oidc.issuerUrl;
                discovery = true;
                uid_field = "preferred_username";
                client_auth_method = "query";
                client_options = {
                  identifier = cfg.oidc.clientId;
                  secret = { _secret = secretPath "gitlab-oidc-secret" cfg.oidc.clientSecretFile; };
                  redirect_uri = "https://${cfg.domain}/users/auth/openid_connect/callback";
                };
              };
            }
          ];
        } // optionalAttrs cfg.oidc.autoLinkExistingUser {
          auto_link_user = [ "openid_connect" ];
        };
      }) cfg.extraConfig;
    };

    # GitLab's workhorse exposes only a unix socket (/run/gitlab is mode
    # 0755 and the socket itself is created world-accessible via
    # `-listenUmask 0`, so no group membership is needed for Caddy).
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyAddress = "unix//run/gitlab/gitlab-workhorse.socket";
      displayName = "GitLab";
      category = "development";
      icon = "gitlab";
    };

    modules.services.vHosts.hosts.${cfg.registry.domain} = mkIf cfg.registry.enable {
      reverseProxyPort = cfg.registry.port;
      displayName = "GitLab Registry";
      category = "development";
      icon = "gitlab";
      # This vhost carries container image layer pushes/pulls — keep it out
      # of Homepage/Gatus noise, it's not a browsable service.
      monitor = false;
      shortcut = false;
    };
  };
}
