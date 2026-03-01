# OpenClaw - Personal AI assistant platform with multi-channel messaging integration
# Provides local AI assistant accessible via WhatsApp, Telegram, Signal, Matrix, Discord, Slack
# Auto-generated Docker compose service configuration
{ config, pkgs, lib, ... }:

let
  domain = "openclaw.${config.networking.domain}";
  gatewayPort = 18789;
  oauthPort = 1455;
  dataDir = "/data/docker-appdata/openclaw";
in
lib.mkIf config.modules.services.ai.openclaw.enable {
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Container
  virtualisation.oci-containers.containers."openclaw" = {
    image = "openclaw-custom:latest";

    environmentFiles = [
      config.age.secrets.openclaw-env.path
    ];

    environment = {
      NODE_ENV = "production";
      OPENCLAW_PORT = toString gatewayPort;
      OPENCLAW_DOMAIN = domain;
    };

    volumes = [
      "${dataDir}/config:/home/node/.openclaw/config:rw"
      "${dataDir}/workspace:/home/node/.openclaw/workspace:rw"
      "${dataDir}/data:/home/node/.openclaw:rw"
    ];

    log-driver = "journald";

    extraOptions = [
      "--network=host"
    ];
  };

  systemd.services."docker-openclaw" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };

    preStart = ''
      docker build -t openclaw-custom:latest -f ${./openclaw.Dockerfile} ${./.}
      mkdir -p ${dataDir}/{config,workspace,data}
      chown -R 1000:1000 ${dataDir}
      chmod -R 755 ${dataDir}

      # Create default config with Matrix enabled if it doesn't exist
      if [ ! -f ${dataDir}/config/openclaw.json ]; then
        cat > ${dataDir}/config/openclaw.json <<'EOF'
{
  "gateway": {
    "mode": "local"
  },
  "plugins": {
    "allow": ["matrix"]
  },
  "channels": {
    "matrix": {
      "enabled": true,
      "dm": {
        "policy": "pairing"
      }
    }
  }
}
EOF
        chown 1000:1000 ${dataDir}/config/openclaw.json
      fi
    '';

    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    partOf = [ "docker-compose-openclaw-root.target" ];
    wantedBy = [ "docker-compose-openclaw-root.target" ];
  };

  # Root service
  systemd.targets."docker-compose-openclaw-root" = {
    unitConfig.Description = "OpenClaw AI assistant root target";
    wantedBy = [ "multi-user.target" ];
  };
}
