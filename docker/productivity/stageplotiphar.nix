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
    # OIDC_ISSUER_URL / OIDC_CLIENT_ID / OIDC_CLIENT_SECRET (Pocket ID) —
    # all three must be set together to turn on multi-user mode; see
    # isMultiUserModeEnabled() in server/src/lib/auth/mode.ts.
    #
    # Secret file/name intentionally still says "stageplotifer": renaming it
    # means decrypting and re-encrypting real OIDC client secret material
    # under a new filename for a purely cosmetic match — not worth touching
    # actual secrets for. The path is internal/invisible either way.
    environmentFiles = [
      config.age.secrets.stageplotifer-oidc-secrets.path
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
    };
    volumes = [
      "stageplotiphar_data:/app/data:rw"
    ];
    ports = [
      "1395:1395/tcp"
    ];
    log-driver = "journald";
    labels = {
      # Scopes the fast-poll watchtower below to just this container —
      # the global docker/watchtower.nix instance still covers everything
      # else at its normal (unconfigured/default) cadence.
      "com.centurylinklabs.watchtower.enable" = "true";
    };
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
    ];
    requires = [
      "docker-network-stageplotiphar_default.service"
      "docker-volume-stageplotiphar_data.service"
      "docker-volume-migrate-stageplotiphar-data.service"
      "docker-login-ghcr-stageplotiphar.service"
    ];
    partOf = [
      "docker-compose-stageplotiphar-root.target"
    ];
    wantedBy = [
      "docker-compose-stageplotiphar-root.target"
    ];
  };

  # Logs the host's root docker client in to GHCR before anything tries to
  # pull the (private) image — both the `docker run` this generates and
  # watchtower-stageplotiphar (via the mounted config.json below) rely on
  # the resulting /root/.docker/config.json.
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

  # Root service
  systemd.targets."docker-compose-stageplotiphar-root" = {
    unitConfig = {
      Description = "Stage Plotiphar stage plot planning tool";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Fast-poll watchtower — testing phase only. Scoped via WATCHTOWER_LABEL_ENABLE
  # to containers carrying the label above, so it only touches stageplotiphar,
  # not every other service on this host. Drop this block (and the label above)
  # once builds have stabilized and the global watchtower's normal cadence is enough.
  virtualisation.oci-containers.containers."watchtower-stageplotiphar" = {
    autoStart = true;
    image = "nickfedor/watchtower";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      # Reuses the same GHCR login docker-login-ghcr-stageplotiphar.service
      # produces — watchtower needs its own read access to pull-check a
      # private image, separate from the host docker CLI's own credential use.
      "/root/.docker/config.json:/config.json:ro"
    ];
    environment = {
      WATCHTOWER_LABEL_ENABLE = "true";
      WATCHTOWER_POLL_INTERVAL = "300"; # 5 minutes
      WATCHTOWER_CLEANUP = "true";
    };
  };

  systemd.services."docker-watchtower-stageplotiphar" = {
    after = [ "docker-login-ghcr-stageplotiphar.service" ];
    requires = [ "docker-login-ghcr-stageplotiphar.service" ];
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
