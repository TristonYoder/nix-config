# Stage Plotifer - Stage plot & mic assignment planning tool for PCO-integrated churches
# Image is built and published by the app's own repo CI (Nix-built,
# ghcr.io/tristonyoder/stageplotifer) — see TristonYoder/stagePlotifer.
# Public at plotiphar.com via david's Cloudflare Tunnel (profiles/server.nix
# enables modules.services.infrastructure.cloudflared) — the tunnel's public
# hostname mapping lives in the Cloudflare dashboard, not in this repo, so
# switching this domain also requires updating that mapping there.
{ config, pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Container
  virtualisation.oci-containers.containers."stageplotifer" = {
    image = "ghcr.io/tristonyoder/stageplotifer:latest";
    # OIDC_ISSUER_URL / OIDC_CLIENT_ID / OIDC_CLIENT_SECRET (Pocket ID) —
    # all three must be set together to turn on multi-user mode; see
    # isMultiUserModeEnabled() in server/src/lib/auth/mode.ts.
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
      "stageplotifer_data:/app/data:rw"
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
      "--network-alias=stageplotifer"
      "--network=stageplotifer_default"
    ];
  };

  systemd.services."docker-stageplotifer" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "10s";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-stageplotifer_default.service"
      "docker-volume-stageplotifer_data.service"
      "docker-login-ghcr-stageplotifer.service"
    ];
    requires = [
      "docker-network-stageplotifer_default.service"
      "docker-volume-stageplotifer_data.service"
      "docker-login-ghcr-stageplotifer.service"
    ];
    partOf = [
      "docker-compose-stageplotifer-root.target"
    ];
    wantedBy = [
      "docker-compose-stageplotifer-root.target"
    ];
  };

  # Logs the host's root docker client in to GHCR before anything tries to
  # pull the (private) image — both the `docker run` this generates and
  # watchtower-stageplotifer (via the mounted config.json below) rely on
  # the resulting /root/.docker/config.json.
  systemd.services."docker-login-ghcr-stageplotifer" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker login ghcr.io -u tristonyoder --password-stdin < ${config.age.secrets.ghcr-pull-token.path}
    '';
    partOf = [ "docker-compose-stageplotifer-root.target" ];
    wantedBy = [ "docker-compose-stageplotifer-root.target" ];
  };

  # Network
  systemd.services."docker-network-stageplotifer_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f stageplotifer_default";
    };
    script = ''
      docker network inspect stageplotifer_default || docker network create stageplotifer_default
    '';
    partOf = [ "docker-compose-stageplotifer-root.target" ];
    wantedBy = [ "docker-compose-stageplotifer-root.target" ];
  };

  # Volume
  systemd.services."docker-volume-stageplotifer_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect stageplotifer_data || docker volume create stageplotifer_data
    '';
    partOf = [ "docker-compose-stageplotifer-root.target" ];
    wantedBy = [ "docker-compose-stageplotifer-root.target" ];
  };

  # Root service
  systemd.targets."docker-compose-stageplotifer-root" = {
    unitConfig = {
      Description = "Stage Plotifer stage plot planning tool";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Fast-poll watchtower — testing phase only. Scoped via WATCHTOWER_LABEL_ENABLE
  # to containers carrying the label above, so it only touches stageplotifer,
  # not every other service on this host. Drop this block (and the label above)
  # once builds have stabilized and the global watchtower's normal cadence is enough.
  virtualisation.oci-containers.containers."watchtower-stageplotifer" = {
    autoStart = true;
    image = "nickfedor/watchtower";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      # Reuses the same GHCR login docker-login-ghcr-stageplotifer.service
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

  systemd.services."docker-watchtower-stageplotifer" = {
    after = [ "docker-login-ghcr-stageplotifer.service" ];
    requires = [ "docker-login-ghcr-stageplotifer.service" ];
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
