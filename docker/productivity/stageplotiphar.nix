# Stage Plotiphar - Stage plot & mic assignment planning tool for PCO-integrated churches
# Image is built and published by the app's own repo CI (Nix-built,
# ghcr.io/tristonyoder/stageplotiphar) — see TristonYoder/stagePlotiphar
# (renamed 2026-07 from stagePlotifer/stageplotifer; GitHub redirects the old
# repo URL). Public at plotiphar.com via david's Cloudflare Tunnel
# (profiles/server.nix enables modules.services.infrastructure.cloudflared)
# — the tunnel's public hostname mapping lives in the Cloudflare dashboard,
# not in this repo, so switching this domain also requires updating that
# mapping there.
{ config, pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Container
  virtualisation.oci-containers.containers."stageplotiphar" = {
    image = "ghcr.io/tristonyoder/stageplotiphar:latest";
    # OIDC_ISSUER_URL / OIDC_CLIENT_ID / OIDC_CLIENT_SECRET (Pocket ID) OR
    # PCO_CLIENT_ID / PCO_CLIENT_SECRET (Planning Center) — at least one full
    # set must be configured to turn on multi-user mode; see
    # isMultiUserModeEnabled() in server/src/lib/auth/mode.ts.
    #
    # Secret file/name intentionally still says "stageplotifer": renaming it
    # means decrypting and re-encrypting real OIDC client secret material
    # under a new filename for a purely cosmetic match — not worth touching
    # actual secrets for. The path is internal/invisible either way.
    environmentFiles = [
      config.age.secrets.stageplotifer-oidc-secrets.path
      # DATABASE_URL (points at stageplotiphar-db below) — shared with that
      # container's own POSTGRES_PASSWORD, same pattern as docmost-secrets.
      config.age.secrets.stageplotiphar-postgres-secrets.path
      # STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET for the optional billing
      # add-on (per-venue subscriptions, 40-day free trial). Stripe test-mode
      # ("demo") credentials — will be rotated before real launch. Billing is
      # inert unless the deployed image was built with the private billing
      # submodule.
      config.age.secrets.stageplotiphar-stripe-secrets.path
      # ADMIN_TOKEN for the private admin server (see ADMIN_PORT below) —
      # only present in images built with the private billing submodule.
      # The app is fail-closed: it refuses to start the admin server without
      # a token of at least 24 chars, so a missing/short secret here just
      # keeps it disabled rather than exposing an unauthenticated port.
      config.age.secrets.stageplotiphar-admin-secrets.path
    ];
    environment = {
      # Public URL the app stamps into PCO plan attachment links (stage plot
      # PDF exports) — used both by the manual "Send to PCO" button and the
      # auto-plot scheduler's auto-send toggle. The scheduler runs on a timer
      # with no incoming request to derive this from Caddy's X-Forwarded-Host,
      # so unlike the request-driven path it has no fallback: without this
      # set, auto-send silently no-ops (logs and skips) instead of crashing.
      # Not a secret — same hostname already appears in the Caddy block below.
      PUBLIC_BASE_URL = "https://plotiphar.com";

      # Label for the generic OIDC authentication provider button
      OIDC_NAME = "Plotiphar";

      # Switches persistence from the default SQLite (a file inside the
      # stageplotiphar_data volume) to the stageplotiphar-db container below.
      # DATABASE_URL comes from the secret file, not here — it embeds the
      # Postgres password.
      DATABASE_TYPE = "postgres";

      # Makes deletes soft (sets a `deleted_at` tombstone) for the entities
      # the offline-first Mac app replicates, so a deletion made here in the
      # web UI actually propagates to those replicas. Without it a delete is
      # a hard row removal, the delta feed has nothing to report, and every
      # offline client keeps the deleted item forever.
      #
      # Deliberately NOT `SYNC_MODE=cloud` — that is the *replica* mode. It
      # additionally enables a client-side outbox whose table only exists in
      # the app's SQLite schema, so setting it on this Postgres-backed server
      # would break on the first write. The two gates are separate for
      # exactly this reason: `SYNC_ENABLED` = "produce tombstones others can
      # sync", `SYNC_MODE=cloud` = "be a replica that syncs".
      #
      # Low blast radius on its own: it only changes delete semantics, and
      # the tombstoned rows are filtered out of every normal read, so the UI
      # behaves identically. The /api/sync/* endpoints it feeds resolve
      # through the same per-org auth as every other route.
      SYNC_ENABLED = "1";

      # Stripe price IDs for the optional billing add-on — not secret (price
      # IDs, unlike the API key/webhook secret above). Stripe test-mode
      # ("demo") prices, rotated before real launch. Billing is inert unless
      # the deployed image was built with the private billing submodule.
      STRIPE_PRICE_MONTHLY = "price_1Tte2NDsDKkan45SGIAzSc3z";
      STRIPE_PRICE_YEARLY = "price_1Tte2NDsDKkan45Ss0vFKWd7";

      # Private admin server (billing add-on) — listens on a second port
      # inside the same container, separate from the public app on 1395.
      # Setting ADMIN_PORT is what turns the admin server on at all; leaving
      # it unset disables it entirely. ADMIN_HOST is intentionally left
      # unset so the app defaults to 0.0.0.0 inside the container — the
      # container's own network namespace already isolates it, and the real
      # privacy boundary is the host port publishing below (127.0.0.1 only)
      # plus the ADMIN_TOKEN gate from the secret file above. This port is
      # deliberately NOT proxied by Caddy and NOT routed through the
      # Cloudflare tunnel (see the Caddy block at the bottom of this file) —
      # it must only ever be reachable privately (localhost / SSH tunnel /
      # Tailscale), never from the public internet.
      ADMIN_PORT = "1396";
    };
    volumes = [
      "stageplotiphar_data:/app/data:rw"
    ];
    ports = [
      "1395:1395/tcp"
      # Admin server: bound to loopback only, matching this repo's
      # established pattern for host-private docker services (see
      # modules/services/productivity/stirling-pdf.nix,
      # modules/services/storage/nextcloud/{onlyoffice,collabora}.nix). No
      # 0.0.0.0 publish, no Caddy vhost, no tunnel route. Reachable from
      # david itself or via `ssh -L 1396:localhost:1396 david`.
      "127.0.0.1:1396:1396/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=stageplotiphar"
      "--network=stageplotiphar_default"
    ];
  };

  systemd.services."docker-stageplotiphar" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "10s";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-stageplotiphar_default.service"
      "docker-volume-stageplotiphar_data.service"
      "docker-volume-migrate-stageplotiphar-data.service"
      "docker-login-ghcr-stageplotiphar.service"
      "docker-stageplotiphar-db.service"
    ];
    requires = [
      "docker-network-stageplotiphar_default.service"
      "docker-volume-stageplotiphar_data.service"
      "docker-volume-migrate-stageplotiphar-data.service"
      "docker-login-ghcr-stageplotiphar.service"
      "docker-stageplotiphar-db.service"
    ];
    partOf = [
      "docker-compose-stageplotiphar-root.target"
    ];
    wantedBy = [
      "docker-compose-stageplotiphar-root.target"
    ];
  };

  # Logs the host's root docker client in to GHCR before anything tries to
  # pull the (private) image — the `docker run` this generates relies on the
  # resulting /root/.docker/config.json.
  systemd.services."docker-login-ghcr-stageplotiphar" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker login ghcr.io -u tristonyoder --password-stdin < ${config.age.secrets.ghcr-pull-token.path}
    '';
    partOf = [ "docker-compose-stageplotiphar-root.target" ];
    wantedBy = [ "docker-compose-stageplotiphar-root.target" ];
  };

  # Postgres database — dedicated container per service, matching the
  # pattern other Docker-backed apps in this repo use (see docker/docmost.nix)
  # rather than the shared native `services.postgresql` instance, so this
  # app's data is isolated from other services on that shared instance.
  virtualisation.oci-containers.containers."stageplotiphar-db" = {
    image = "postgres:16-alpine";
    environmentFiles = [
      config.age.secrets.stageplotiphar-postgres-secrets.path
    ];
    environment = {
      "POSTGRES_DB" = "stageplotiphar";
      "POSTGRES_USER" = "stageplotiphar";
      # POSTGRES_PASSWORD loaded from the same secret file as the app
      # container's DATABASE_URL above — must be the same value.
    };
    volumes = [
      "stageplotiphar_db_data:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=stageplotiphar-db"
      "--network=stageplotiphar_default"
    ];
  };

  systemd.services."docker-stageplotiphar-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "10s";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-stageplotiphar_default.service"
      "docker-volume-stageplotiphar_db_data.service"
    ];
    requires = [
      "docker-network-stageplotiphar_default.service"
      "docker-volume-stageplotiphar_db_data.service"
    ];
    partOf = [
      "docker-compose-stageplotiphar-root.target"
    ];
    wantedBy = [
      "docker-compose-stageplotiphar-root.target"
    ];
  };

  # Network
  systemd.services."docker-network-stageplotiphar_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f stageplotiphar_default";
    };
    script = ''
      docker network inspect stageplotiphar_default || docker network create stageplotiphar_default
    '';
    partOf = [ "docker-compose-stageplotiphar-root.target" ];
    wantedBy = [ "docker-compose-stageplotiphar-root.target" ];
  };

  # Volume
  systemd.services."docker-volume-stageplotiphar_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect stageplotiphar_data || docker volume create stageplotiphar_data
    '';
    partOf = [ "docker-compose-stageplotiphar-root.target" ];
    wantedBy = [ "docker-compose-stageplotiphar-root.target" ];
  };

  systemd.services."docker-volume-stageplotiphar_db_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect stageplotiphar_db_data || docker volume create stageplotiphar_db_data
    '';
    partOf = [ "docker-compose-stageplotiphar-root.target" ];
    wantedBy = [ "docker-compose-stageplotiphar-root.target" ];
  };

  # One-time migration of the real (Fishers church) data from the
  # pre-rename volume name. Idempotent and defensive: only copies when the
  # new volume looks empty and the old volume actually exists, so it's safe
  # to leave in place across every future rebuild — after the first
  # successful copy it's just a no-op check. Never deletes stageplotifer_data
  # (the old volume), so there's always a fallback to roll back to.
  systemd.services."docker-volume-migrate-stageplotiphar-data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -z "$(docker run --rm -v stageplotiphar_data:/to alpine sh -c 'ls -A /to')" ]; then
        if docker volume inspect stageplotifer_data >/dev/null 2>&1; then
          echo "Migrating stageplotifer_data -> stageplotiphar_data..."
          docker run --rm -v stageplotifer_data:/from:ro -v stageplotiphar_data:/to alpine sh -c 'cp -a /from/. /to/'
        fi
      fi
    '';
    after = [ "docker-volume-stageplotiphar_data.service" ];
    requires = [ "docker-volume-stageplotiphar_data.service" ];
    partOf = [ "docker-compose-stageplotiphar-root.target" ];
    wantedBy = [ "docker-compose-stageplotiphar-root.target" ];
  };

  # Daily snapshots — Postgres logical dump + the app data volume.
  #
  # Lives under /data/docker-appdata rather than /data/backups on purpose:
  # /data/backups is a browsable Samba share (see modules/services/storage/
  # samba.nix) and this dump contains every tenant's data. Mode 0700 root:root
  # keeps it unreadable to NFS clients too — /data/docker-appdata is exported
  # rw but without no_root_squash, so a remote root maps to nobody.
  systemd.tmpfiles.rules = [
    "d /data/docker-appdata/stageplotiphar 0700 root root -"
    "d /data/docker-appdata/stageplotiphar/snapshots 0700 root root -"
  ];

  systemd.services."stageplotiphar-snapshot" = {
    description = "Daily snapshot of Stage Plotiphar database and data volume";
    path = [ pkgs.docker pkgs.gzip pkgs.findutils pkgs.coreutils ];
    after = [ "docker-stageplotiphar-db.service" ];
    requires = [ "docker-stageplotiphar-db.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "1h";
      SyslogIdentifier = "stageplotiphar-snapshot";
    };
    script = ''
      set -euo pipefail

      DEST=/data/docker-appdata/stageplotiphar/snapshots
      STAMP="$(date +%Y-%m-%d)"

      # Postgres — the authoritative store (DATABASE_TYPE=postgres above).
      # Run inside the db container so the credentials come from that
      # container's own environment; the password only ever exists in the
      # agenix env file, never on the host filesystem or in this script.
      docker exec stageplotiphar-db sh -c \
        'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
        | gzip -c > "$DEST/db-$STAMP.sql.gz.partial"
      mv "$DEST/db-$STAMP.sql.gz.partial" "$DEST/db-$STAMP.sql.gz"

      # /app/data volume — uploads and generated PDF exports. Taken live
      # rather than stopping the app: these are whole files written once, and
      # anything relational that would need a consistent point-in-time view is
      # in the Postgres dump above.
      docker run --rm \
        -v stageplotiphar_data:/from:ro \
        -v "$DEST":/to \
        alpine tar czf "/to/data-$STAMP.tar.gz.partial" -C /from .
      mv "$DEST/data-$STAMP.tar.gz.partial" "$DEST/data-$STAMP.tar.gz"

      # Retention. The .partial sweep cleans up after a dump that died
      # mid-write — `set -o pipefail` means the mv is skipped in that case, so
      # a truncated file is never promoted to a real snapshot name.
      find "$DEST" -maxdepth 1 -type f -name '*.gz' -mtime +14 -delete
      find "$DEST" -maxdepth 1 -type f -name '*.partial' -mtime +1 -delete
    '';
  };

  systemd.timers."stageplotiphar-snapshot" = {
    description = "Run the Stage Plotiphar snapshot daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # Root service
  systemd.targets."docker-compose-stageplotiphar-root" = {
    unitConfig = {
      Description = "Stage Plotiphar stage plot planning tool";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Caddy reverse proxy
  services.caddy.virtualHosts."plotiphar.com" = {
    extraConfig = ''
      reverse_proxy http://localhost:1395 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
      }

      import cloudflare_tls
    '';
  };
}
