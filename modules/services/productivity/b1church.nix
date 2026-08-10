# B1 Church — self-hosted ChurchApps stack (church management software).
#
# Four containers, mirroring upstream's docker-compose.yml:
#   mysql   — MySQL 8.4, seven logical databases (one per API module)
#   api     — ChurchApps/Api, an Express modular monolith on :8084
#   admin   — ChurchApps/B1Admin, a Vite SPA (staff-facing admin UI)
#   portal  — ChurchApps/B1App, a Next.js member portal (multi-tenant)
#
# IMAGES: ChurchApps publishes none — ghcr.io/churchapps/* denies pulls and
# their Docker Hub org is empty, so upstream's compose builds from Git contexts
# at `docker compose up` time. A separate build repo tracks upstream `main`
# nightly, builds all three, and pushes SHA-tagged images here. Set
# `imageTag` to the SHA you want; it is deliberately not `latest` so upstream
# breakage never lands unattended.
#
# BUILD-TIME URLS: B1Admin is a Vite SPA — REACT_APP_* are baked into the
# bundle by `vite build` (see its Dockerfile ARG/ENV block), NOT read at
# runtime. The same is true of B1App's NEXT_PUBLIC_*. That means changing
# `domain` or `portalDomain` requires rebuilding the images, not just
# restarting the containers. The build repo takes these as build args.
#
# PUBLIC EXPOSURE: david's cloudflared is token-based and remotely managed
# (profiles/server.nix), so the public hostname → tunnel mapping lives in the
# Cloudflare Zero Trust dashboard, not in this repo — same as plotiphar.com
# itself (docker/productivity/stageplotiphar.nix). Enabling this module gets
# Caddy serving; you still have to add the routes there.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.productivity.b1church;

  # Public origin of the API. It is same-origin with the admin UI: Caddy
  # mounts the API under /api on the admin host rather than giving it its own
  # hostname. The Api is a plain Express app mounting /membership,
  # /attendance, /content, /doing, /giving, /messaging and /reporting — all
  # relative, with no absolute-URL assumptions except CONTENT_ROOT, which is
  # an env var we set below. So prefix-stripping is safe.
  apiBase = "https://${cfg.domain}${cfg.apiPath}";

  # Uploaded files (FILE_STORE=disk). The Api serves these back itself from
  # express.static("content") and stamps CONTENT_ROOT into the URLs it
  # returns, so this must be the externally reachable form.
  contentRoot = "${apiBase}/content";

  # Same origin, upgraded scheme. The Api's WebSocket server shares the HTTP
  # listener, so it rides the same prefix and Caddy upgrades it transparently.
  socketUrl = "wss://${cfg.domain}${cfg.apiPath}";

  adminUrl = "https://${cfg.domain}";

  # B1App is multi-tenant by subdomain: next.config.mjs rewrites on the
  # `host` / `x-site` header to serve each church's own site. The literal
  # "{subdomain}" is a placeholder B1Admin substitutes per church at runtime
  # (see EnvironmentHelper.B1Url) — it is not a Nix interpolation.
  portalUrlTemplate = "https://{subdomain}.${cfg.portalBaseDomain}";

  dataDir = cfg.dataDir;
in
{
  options.modules.services.productivity.b1church = {
    enable = mkEnableOption "B1 Church self-hosted ChurchApps stack";

    domain = mkOption {
      type = types.str;
      default = "b1.${config.networking.domain}";
      description = "Hostname serving the B1Admin UI, with the API mounted under apiPath.";
    };

    portalBaseDomain = mkOption {
      type = types.str;
      default = "b1.${config.networking.domain}";
      description = ''
        Base domain for member portal sites. Each church is served at
        <subdomain>.<portalBaseDomain>, so Caddy gets a wildcard vHost for it.
        Requires a wildcard TLS cert (DNS-01) and a wildcard tunnel route.
      '';
    };

    apiPath = mkOption {
      type = types.str;
      default = "/api";
      description = ''
        Path prefix under `domain` where the API is mounted. Caddy strips
        this before proxying. Must not collide with a B1Admin client route.
      '';
    };

    corsOrigin = mkOption {
      type = types.str;
      default = "*";
      description = ''
        CORS_ORIGIN for the Api — a comma-separated list of exact origins, or
        "*". Defaults to "*" (upstream's default) because the Api matches
        origins with an exact `includes()` check and cannot express the
        wildcard subdomain the member portal is served from. Auth is a Bearer
        JWT rather than a cookie, so a permissive origin does not by itself
        allow a third-party site to act as a signed-in user.
      '';
    };

    supportEmail = mkOption {
      type = types.str;
      default = "";
      description = "Address used as the From/reply-to for transactional mail.";
    };

    smtp = {
      host = mkOption {
        type = types.str;
        default = "smtp.mailgun.org";
        description = "SMTP relay hostname. SMTP_USER/SMTP_PASS come from the api secret file.";
      };
      port = mkOption {
        type = types.port;
        default = 587;
        description = "SMTP port. 587 is STARTTLS, 465 is implicit TLS (set secure = true).";
      };
      secure = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use implicit TLS (port 465) rather than STARTTLS.";
      };
    };

    imageBase = mkOption {
      type = types.str;
      default = "ghcr.io/tristonyoder/b1church";
      description = "Registry path prefix; each component appends -api / -admin / -portal.";
    };

    imageTag = mkOption {
      type = types.str;
      default = "latest";
      description = ''
        Tag to deploy. Pin to a sha-<commit> tag produced by the nightly build
        so an upstream regression cannot deploy itself; bump deliberately.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/b1church";
      description = ''
        Parent for MySQL data, uploaded content and snapshots. Lives on
        david's ZFS pool so it inherits the pool snapshot policy. Mode 0700
        root:root — /data/docker-appdata is NFS-exported without
        no_root_squash, so a remote root maps to nobody.
      '';
    };

    apiPort = mkOption {
      type = types.port;
      default = 8084;
      description = "Loopback host port for the Api container.";
    };

    adminPort = mkOption {
      type = types.port;
      default = 3101;
      description = "Loopback host port for the B1Admin container.";
    };

    portalPort = mkOption {
      type = types.port;
      default = 3102;
      description = "Loopback host port for the B1App member portal container.";
    };

    snapshots = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Daily mysqldump plus a tar of uploaded content.";
      };
      retentionDays = mkOption {
        type = types.int;
        default = 14;
        description = "How long to keep snapshot files.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = hasPrefix "/" cfg.apiPath && !(hasSuffix "/" cfg.apiPath);
        message = "b1church.apiPath must start with / and must not end with / (got \"${cfg.apiPath}\").";
      }
    ];

    warnings = optional (cfg.imageTag == "latest")
      "b1church.imageTag is \"latest\" — upstream main is rebuilt nightly, so a regression can deploy unattended. Pin a sha-<commit> tag.";

    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    # ── Storage ───────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0700 root root -"
      # MySQL's container user is uid/gid 999.
      "d ${dataDir}/mysql 0700 999 999 -"
      "d ${dataDir}/content 0755 root root -"
      "d ${dataDir}/snapshots 0700 root root -"
    ];

    # ── MySQL ─────────────────────────────────────────────────────────────
    virtualisation.oci-containers.containers."b1church-mysql" = {
      image = "mysql:8.4";
      # MYSQL_ROOT_PASSWORD, plus the seven *_CONNECTION_STRING values the Api
      # reads. They embed the same password, so they share one secret file —
      # the value then exists in exactly one place. MySQL ignores the extra
      # variables.
      environmentFiles = [ config.age.secrets.b1church-db-secrets.path ];
      volumes = [ "${dataDir}/mysql:/var/lib/mysql:rw" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=mysql"
        "--network=b1church_default"
        "--health-cmd=mysqladmin ping -h 127.0.0.1 -uroot -p\"$MYSQL_ROOT_PASSWORD\""
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=30"
      ];
    };

    # ── Api ───────────────────────────────────────────────────────────────
    virtualisation.oci-containers.containers."b1church-api" = {
      image = "${cfg.imageBase}-api:${cfg.imageTag}";
      environmentFiles = [
        # JWT_SECRET, ENCRYPTION_KEY, SMTP_USER, SMTP_PASS.
        config.age.secrets.b1church-api-secrets.path
        # The *_CONNECTION_STRING values — same file MySQL reads its root
        # password from, so the two can never drift apart.
        config.age.secrets.b1church-db-secrets.path
      ];
      environment = {
        ENVIRONMENT = "docker";
        # Turns on the self-hosted code path: local auth, and the first
        # account registered becomes the server admin.
        SELF_HOSTED = "1";
        SERVER_PORT = "8084";

        CORS_ORIGIN = cfg.corsOrigin;

        # Uploads go to a bind-mounted directory rather than S3, and the Api
        # serves them back from express.static("content").
        FILE_STORE = "disk";
        DELIVERY_PROVIDER = "local";
        CONTENT_ROOT = contentRoot;

        SOCKET_URL = socketUrl;
        B1ADMIN_ROOT = adminUrl;

        SUPPORT_EMAIL = cfg.supportEmail;
        MAIL_SYSTEM = "SMTP";
        SMTP_HOST = cfg.smtp.host;
        SMTP_PORT = toString cfg.smtp.port;
        SMTP_SECURE = boolToString cfg.smtp.secure;
      };
      volumes = [ "${dataDir}/content:/app/content:rw" ];
      ports = [ "127.0.0.1:${toString cfg.apiPort}:8084/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=api"
        "--network=b1church_default"
      ];
    };

    # ── B1Admin (SPA) ─────────────────────────────────────────────────────
    # All of this app's configuration was baked in at image build time; the
    # container only serves the built bundle.
    virtualisation.oci-containers.containers."b1church-admin" = {
      image = "${cfg.imageBase}-admin:${cfg.imageTag}";
      environment.PORT = "3101";
      ports = [ "127.0.0.1:${toString cfg.adminPort}:3101/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=admin"
        "--network=b1church_default"
      ];
    };

    # ── B1App (member portal) ─────────────────────────────────────────────
    virtualisation.oci-containers.containers."b1church-portal" = {
      image = "${cfg.imageBase}-portal:${cfg.imageTag}";
      environment.PORT = "3000";
      ports = [ "127.0.0.1:${toString cfg.portalPort}:3000/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=portal"
        "--network=b1church_default"
      ];
    };

    # ── Ordering ──────────────────────────────────────────────────────────
    systemd.services."docker-network-b1church_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "docker network rm -f b1church_default";
      };
      script = ''
        docker network inspect b1church_default || docker network create b1church_default
      '';
      partOf = [ "b1church-root.target" ];
      wantedBy = [ "b1church-root.target" ];
    };

    # oci-containers has no equivalent of compose's `depends_on: condition:
    # service_healthy`, and the Api exits rather than retrying if the seven
    # module connections fail at boot. Gate on the container healthcheck.
    systemd.services."b1church-wait-mysql" = {
      description = "Wait for B1 Church MySQL to report healthy";
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      script = ''
        set -eu
        for _ in $(seq 1 150); do
          status=$(docker inspect -f '{{.State.Health.Status}}' b1church-mysql 2>/dev/null || echo starting)
          [ "$status" = "healthy" ] && exit 0
          sleep 2
        done
        echo "b1church-mysql did not become healthy in time" >&2
        exit 1
      '';
      after = [ "docker-b1church-mysql.service" ];
      requires = [ "docker-b1church-mysql.service" ];
      partOf = [ "b1church-root.target" ];
      wantedBy = [ "b1church-root.target" ];
    };

    systemd.services."docker-b1church-mysql" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartSec = lib.mkOverride 90 "10s";
      };
      after = [ "docker-network-b1church_default.service" ];
      requires = [ "docker-network-b1church_default.service" ];
      partOf = [ "b1church-root.target" ];
      wantedBy = [ "b1church-root.target" ];
    };

    systemd.services."docker-b1church-api" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartSec = lib.mkOverride 90 "10s";
      };
      after = [ "b1church-wait-mysql.service" ];
      requires = [ "b1church-wait-mysql.service" ];
      partOf = [ "b1church-root.target" ];
      wantedBy = [ "b1church-root.target" ];
    };

    systemd.services."docker-b1church-admin" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartSec = lib.mkOverride 90 "10s";
      };
      after = [ "docker-network-b1church_default.service" ];
      requires = [ "docker-network-b1church_default.service" ];
      partOf = [ "b1church-root.target" ];
      wantedBy = [ "b1church-root.target" ];
    };

    systemd.services."docker-b1church-portal" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartSec = lib.mkOverride 90 "10s";
      };
      after = [ "docker-network-b1church_default.service" ];
      requires = [ "docker-network-b1church_default.service" ];
      partOf = [ "b1church-root.target" ];
      wantedBy = [ "b1church-root.target" ];
    };

    systemd.targets."b1church-root" = {
      unitConfig.Description = "B1 Church self-hosted ChurchApps stack";
      wantedBy = [ "multi-user.target" ];
    };

    # ── Snapshots ─────────────────────────────────────────────────────────
    systemd.services."b1church-snapshot" = mkIf cfg.snapshots.enable {
      description = "Daily snapshot of B1 Church databases and uploaded content";
      path = [ pkgs.docker pkgs.gzip pkgs.findutils pkgs.coreutils ];
      after = [ "docker-b1church-mysql.service" ];
      requires = [ "docker-b1church-mysql.service" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "1h";
        SyslogIdentifier = "b1church-snapshot";
      };
      script = ''
        set -euo pipefail

        DEST=${dataDir}/snapshots
        STAMP="$(date +%Y-%m-%d)"

        # Run mysqldump inside the container so the root password comes from
        # that container's own environment — it never lands on the host
        # filesystem or in this script. --single-transaction keeps the dump
        # consistent without locking out the running Api.
        docker exec b1church-mysql sh -c \
          'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --all-databases' \
          | gzip -c > "$DEST/db-$STAMP.sql.gz.partial"
        mv "$DEST/db-$STAMP.sql.gz.partial" "$DEST/db-$STAMP.sql.gz"

        # Uploaded files. Taken live rather than stopping the Api: these are
        # whole files written once, and everything relational that needs a
        # point-in-time view is in the dump above.
        tar czf "$DEST/content-$STAMP.tar.gz.partial" -C ${dataDir}/content .
        mv "$DEST/content-$STAMP.tar.gz.partial" "$DEST/content-$STAMP.tar.gz"

        # `set -o pipefail` means the mv is skipped if a dump dies mid-write,
        # so a truncated file is never promoted to a real snapshot name; the
        # .partial sweep cleans those up.
        find "$DEST" -maxdepth 1 -type f -name '*.gz' -mtime +${toString cfg.snapshots.retentionDays} -delete
        find "$DEST" -maxdepth 1 -type f -name '*.partial' -mtime +1 -delete
      '';
    };

    systemd.timers."b1church-snapshot" = mkIf cfg.snapshots.enable {
      description = "Run the B1 Church snapshot daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };

    # ── Reverse proxy ─────────────────────────────────────────────────────
    # dnsRecord = false: these are plotiphar.com names, and the Technitium
    # provider would otherwise create a forwarder zone for the whole
    # plotiphar.com apex on the internal resolver.
    modules.services.vHosts.hosts.${cfg.domain} = {
      public = true;
      dnsRecord = false;
      rawConfig = true;
      displayName = "B1 Church";
      category = "productivity";
      icon = "church";
      extraConfig = ''
        # API first — everything not under ${cfg.apiPath} belongs to the SPA,
        # which does its own client-side routing.
        @api path ${cfg.apiPath} ${cfg.apiPath}/*
        handle @api {
          uri strip_prefix ${cfg.apiPath}
          reverse_proxy http://127.0.0.1:${toString cfg.apiPort} {
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Host {host}
          }
        }

        handle {
          reverse_proxy http://127.0.0.1:${toString cfg.adminPort} {
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Host {host}
          }
        }
      '';
    };

    # Wildcard vHost for the member portal. B1App resolves the church from
    # the host / x-site header (next.config.mjs), so every church subdomain
    # is served by the one container. Needs a wildcard cert, which is why
    # dnsChallenge stays on — the Cloudflare API token must cover this zone.
    modules.services.vHosts.hosts."*.${cfg.portalBaseDomain}" = {
      public = true;
      dnsRecord = false;
      rawConfig = true;
      # Gatus cannot probe a wildcard, and it is not a single app tile.
      monitor = false;
      shortcut = false;
      # A literal "*.…" line in /etc/hosts resolves nothing — glob syntax is
      # not supported there — so skip the entry the registry adds by default.
      localHostsEntry = false;
      displayName = "B1 Church Portal";
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.portalPort} {
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
          # next.config.mjs rewrites on x-site when present, host otherwise.
          # Setting it explicitly keeps tenant resolution correct even if a
          # future proxy hop rewrites Host.
          header_up X-Site {host}
        }
      '';
    };

    # Surfaced for the build repo: these are the values the images must be
    # built with, and they are only correct if they match this config.
    environment.etc."b1church/build-args.env".text = ''
      # Generated by modules/services/productivity/b1church.nix — the build
      # repo must pass these as --build-arg for the deployed images to talk
      # to the right hosts. Vite/Next bake them in; they are not read at
      # runtime.
      API_URL=${apiBase}
      CONTENT_ROOT=${contentRoot}
      SOCKET_URL=${socketUrl}
      B1ADMIN_URL=${adminUrl}
      B1APP_URL=${portalUrlTemplate}
    '';
  };
}
