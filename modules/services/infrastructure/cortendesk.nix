{ config, lib, pkgs, ... }:

# CortenDesk — self-hosted RustDesk server and admin console in one container:
# its own fork of hbbs/hbbr (ID + relay), a Laravel console and client API, and
# an in-browser client. https://github.com/marcpope/cortendesk
#
# Runs on pits (public IP), so clients outside the LAN reach the ID/relay ports
# without port forwarding. The console goes through Caddy on `domain`; the raw
# RustDesk ports are published straight from the container on the same name.
# The public A records (DNS only, not proxied) live in Cloudflare, because
# Cloudflare's proxy can't carry the RustDesk ports.
#
# The admin password comes from the agenix secret cortendesk-env
# (CORTENDESK_ADMIN_PASSWORD=..., read on first boot only). Read it with
# `secrets/decrypt-secret.sh cortendesk-env.age`. The console stays
# internal-only (LAN + Tailscale) until `public = true`.
#
# The server private key comes from the agenix secret cortendesk-private-key
# and is installed over <dataDir>/rustdesk/id_ed25519 on every start, so the
# identity survives losing the data dir. Its public half (id_ed25519.pub, also
# on Settings in the console) is not secret and is home/modules/rustdesk.nix's
# `key` default. Rotating means re-encrypting the secret and updating that key.

with lib;
let
  cfg = config.modules.services.infrastructure.cortendesk;
in
{
  options.modules.services.infrastructure.cortendesk = {
    enable = mkEnableOption "CortenDesk RustDesk server and console";

    image = mkOption {
      type = types.str;
      # Pinned: the project ships fast (v2.0 is in beta). Bump deliberately.
      default = "ghcr.io/marcpope/cortendesk:1.23.0";
      description = "CortenDesk container image.";
    };

    domain = mkOption {
      type = types.str;
      default = "remote.${config.networking.domain}";
      description = "Console URL host, and the ID/relay server name clients use.";
    };

    aliases = mkOption {
      type = types.listOf types.str;
      default = [ "rustdesk.${config.networking.domain}" ];
      description = "Extra names for the console vHost and DNS.";
    };

    consolePort = mkOption {
      type = types.port;
      default = 21114;
      description = "Loopback port Caddy proxies the console and client API to.";
    };

    public = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Expose the console and client API to the internet. When false, Caddy
        only answers LAN and Tailscale addresses. The ID/relay ports are public
        either way.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/cortendesk";
      description = "Host path for /data: SQLite DB, settings, key pair, backups.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = config.age.secrets.cortendesk-env.path;
      defaultText = literalExpression "config.age.secrets.cortendesk-env.path";
      example = "/run/agenix/cortendesk-env";
      description = ''
        Optional KEY=VALUE file for secrets, e.g. CORTENDESK_ADMIN_PASSWORD
        (read on first boot only).
      '';
    };

    privateKeyFile = mkOption {
      type = types.nullOr types.str;
      default = config.age.secrets.cortendesk-private-key.path;
      defaultText = literalExpression "config.age.secrets.cortendesk-private-key.path";
      description = "Server private key (id_ed25519 contents). Null lets the container generate one.";
    };

    # SSO for the console and RustDesk clients. When enabled, these settings
    # are written into CortenDesk's settings table after every container start
    # and on every switch, overriding edits made on Settings -> SSO. Settings
    # not listed here (default group, allowed domains, ...) stay UI-managed.
    # Disabling this stops managing them; it does not turn SSO off.
    oidc = {
      enable = mkEnableOption "declarative OIDC (SSO) settings";

      issuer = mkOption {
        type = types.str;
        default = "https://id.${config.networking.domain}";
        description = "OIDC issuer; /.well-known/openid-configuration is appended by CortenDesk.";
      };

      clientId = mkOption {
        type = types.str;
        description = "Client ID of the CortenDesk client at the provider. Not a secret.";
      };

      clientSecretFile = mkOption {
        type = types.str;
        default = config.age.secrets.cortendesk-oidc-secret.path;
        defaultText = literalExpression "config.age.secrets.cortendesk-oidc-secret.path";
        description = "File holding the client secret.";
      };

      buttonLabel = mkOption {
        type = types.str;
        default = "Pocket ID";
        description = "Label for the SSO button (login page and RustDesk client).";
      };

      newUserPolicy = mkOption {
        type = types.enum [ "deny" "pending" "active" ];
        default = "active";
        description = "What happens to a provider user with no console account. New accounts are never admins.";
      };

      logout = mkOption {
        type = types.bool;
        default = true;
        description = "Also end the provider session on console logout.";
      };

      disableLocalLogin = mkOption {
        type = types.bool;
        default = false;
        description = "Hide password sign-in. Leave off to keep the admin password as a break-glass login.";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 root root -" ];

    virtualisation.oci-containers.containers.cortendesk = {
      image = cfg.image;
      environment = {
        # Everything else (relay address handed to clients, web client wss
        # URLs) is derived from this.
        APP_URL = "https://${cfg.domain}";
        TZ = config.time.timeZone;
      } // optionalAttrs (cfg.privateKeyFile != null) {
        CORTENDESK_PRIVATE_KEY_FILE = "/run/secrets/rustdesk_key";
      };
      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;
      volumes = [ "${cfg.dataDir}:/data" ]
        ++ optional (cfg.privateKeyFile != null) "${cfg.privateKeyFile}:/run/secrets/rustdesk_key:ro";
      ports = [
        "127.0.0.1:${toString cfg.consolePort}:8080"
        "21115:21115"     # NAT test
        "21116:21116"     # signalling
        "21116:21116/udp"
        "21117:21117"     # relay
        # 21118/21119 (WebSocket) stay unpublished: nginx in the container
        # bridges /ws/id and /ws/relay over loopback, reached via Caddy.
      ];
    };

    systemd.services.cortendesk-oidc = mkIf cfg.oidc.enable (
      let
        settings = builtins.toJSON {
          oidc_enabled = "1";
          oidc_discovery_url = removeSuffix "/" cfg.oidc.issuer;
          oidc_client_id = cfg.oidc.clientId;
          oidc_scopes = "openid email profile";
          oidc_button_label = cfg.oidc.buttonLabel;
          oidc_new_user_policy = cfg.oidc.newUserPolicy;
          oidc_logout_enabled = if cfg.oidc.logout then "1" else "0";
          oidc_disable_local_login = if cfg.oidc.disableLocalLogin then "1" else "0";
        };
        # Same writes as Settings -> SSO (app/Livewire/SettingsPage.php):
        # plain rows, the secret through Crypt::encryptString.
        phpHead = pkgs.writeText "cortendesk-oidc-head.php" ''
          <?php
          require '/app/vendor/autoload.php';
          $app = require '/app/bootstrap/app.php';
          $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
          $settings = json_decode(<<<'JSON'
          ${settings}
          JSON, true);
          foreach ($settings as $k => $v) { \App\Models\Setting::put($k, $v); }
        '';
        phpTail = pkgs.writeText "cortendesk-oidc-tail.php" ''
          $cur = \App\Models\Setting::get('oidc_client_secret');
          $old = null;
          if ($cur) { try { $old = \Illuminate\Support\Facades\Crypt::decryptString($cur); } catch (\Throwable $e) {} }
          if ($old !== $secret) {
            \App\Models\Setting::put('oidc_client_secret', \Illuminate\Support\Facades\Crypt::encryptString($secret));
            echo "client secret updated\n";
          }
          echo "OIDC settings applied\n";
        '';
      in
      {
        description = "Apply CortenDesk OIDC settings";
        after = [ "docker-cortendesk.service" ];
        requires = [ "docker-cortendesk.service" ];
        partOf = [ "docker-cortendesk.service" ];
        wantedBy = [ "docker-cortendesk.service" ];
        restartTriggers = [ phpHead phpTail ];
        path = [ config.virtualisation.docker.package pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # First start can include an image pull; wait for the app to be up.
          for _ in $(seq 1 120); do
            [ "$(docker inspect -f '{{.State.Health.Status}}' cortendesk 2>/dev/null)" = healthy ] && break
            sleep 5
          done
          # PHP and secret go in over stdin (printf is a builtin): never in argv.
          {
            cat ${phpHead}
            printf "\$secret = trim(base64_decode('%s'));\n" "$(base64 -w0 < ${escapeShellArg cfg.oidc.clientSecretFile})"
            cat ${phpTail}
          } | docker exec -i -u www-data -w /app cortendesk php
        '';
      }
    );

    networking.firewall.allowedTCPPorts = [ 21115 21116 21117 ];
    networking.firewall.allowedUDPPorts = [ 21116 ];

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.consolePort;
      serverAliases = cfg.aliases;
      public = cfg.public;
      displayName = "CortenDesk";
      category = "infrastructure";
      icon = "rustdesk";
    };
  };
}
