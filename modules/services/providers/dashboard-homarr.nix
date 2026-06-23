{ config, lib, pkgs, ... }:

# ── Homarr dashboard provider ─────────────────────────────────────────────────
#
# API-driven dashboard: each host runs a homarr-sync activation script that
# POSTs its vHosts into the central Homarr instance on david (or wherever
# homarr.enable = true). This mirrors the dns-technitium pattern — any host
# can register its services into one unified dashboard.
#
# Usage:
#
#   On the host running Homarr:
#     modules.services.providers.dashboard-homarr.enable = true;
#
#   On any host that should register its services into that central Homarr:
#     modules.services.providers.dashboard-homarr = {
#       sync.enable = true;
#       sync.url = "http://david.theyoder.family:7575";
#       sync.apiKeyFile = config.age.secrets.homarr-api-key.path;
#     };
#
# ─────────────────────────────────────────────────────────────────────────────

with lib;

let
  cfg = config.modules.services.providers.dashboard-homarr;

  syncHosts = filter (h: h.enable)
    (attrValues config.modules.services.vHosts.hosts);

  # Build the JSON payload for one vHost entry
  toAppJson = h: builtins.toJSON {
    name        = h.displayName;
    url         = "https://${h.virtualHost}";
    icon        = if h.icon != "" then h.icon else null;
    description = h.category;
  };

  homarrSyncScript = pkgs.writeShellScript "homarr-sync" ''
    set -eo pipefail

    HOMARR_URL="${cfg.sync.url}"
    API_KEY=$(cat "${cfg.sync.apiKeyFile}")
    CURL="${pkgs.curl}/bin/curl"
    JQ="${pkgs.jq}/bin/jq"

    echo "=== homarr-sync: registering ${toString (builtins.length syncHosts)} services ==="

    # Fetch existing apps so we can upsert (update if present, create if not)
    EXISTING=$($CURL -sf \
      -H "Authorization: Bearer $API_KEY" \
      "$HOMARR_URL/api/apps" || echo "[]")

    ${concatMapStringsSep "\n" (h: ''
      NAME=${escapeShellArg h.displayName}
      URL="https://${h.virtualHost}"
      ICON=${escapeShellArg (if h.icon != "" then h.icon else "")}
      CATEGORY=${escapeShellArg h.category}

      EXISTING_ID=$(echo "$EXISTING" | $JQ -r --arg name "$NAME" \
        '.[] | select(.name == $name) | .id // empty' | head -1)

      if [ -n "$EXISTING_ID" ]; then
        echo "  ~ $NAME (update)"
        $CURL -sf -X PATCH \
          -H "Authorization: Bearer $API_KEY" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$NAME\",\"url\":\"$URL\",\"icon\":\"$ICON\",\"description\":\"$CATEGORY\"}" \
          "$HOMARR_URL/api/apps/$EXISTING_ID" | $JQ -r '.name' || true
      else
        echo "  + $NAME (create)"
        $CURL -sf -X POST \
          -H "Authorization: Bearer $API_KEY" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$NAME\",\"url\":\"$URL\",\"icon\":\"$ICON\",\"description\":\"$CATEGORY\"}" \
          "$HOMARR_URL/api/apps" | $JQ -r '.name' || true
      fi
    '') syncHosts}

    echo "=== homarr-sync: complete ==="
  '';
in
{
  options.modules.services.providers.dashboard-homarr = {
    enable = mkEnableOption "Homarr dashboard (run the Homarr container on this host)";

    port = mkOption {
      type = types.port;
      default = 7575;
      description = "Port Homarr listens on.";
    };

    domain = mkOption {
      type = types.str;
      default = "home.${config.networking.domain}";
      description = "Domain to expose Homarr on (registered as a vHost automatically).";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/ajnart/homarr:latest";
      description = "Homarr Docker image.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/homarr";
      description = "Host path for Homarr persistent data.";
    };

    sync = {
      enable = mkEnableOption "Homarr sync — register this host's vHosts into a Homarr instance at activation";

      url = mkOption {
        type = types.str;
        default = "http://localhost:${toString cfg.port}";
        description = "Base URL of the Homarr instance to sync into.";
      };

      apiKeyFile = mkOption {
        type = types.path;
        default =
          if config.age.secrets ? homarr-api-key
          then config.age.secrets.homarr-api-key.path
          else "/run/agenix/homarr-api-key";
        description = "Path to file containing the Homarr API key.";
      };
    };
  };

  config = mkMerge [
    # ── Run the Homarr container ──────────────────────────────────────────────
    (mkIf cfg.enable {
      virtualisation.oci-containers.containers.homarr = {
        image = cfg.image;
        ports = [ "${toString cfg.port}:7575" ];
        volumes = [
          "${cfg.dataDir}/configs:/app/data/configs"
          "${cfg.dataDir}/icons:/app/public/icons"
          "${cfg.dataDir}/data:/data"
        ];
        environment = {
          PORT = toString cfg.port;
        };
        extraOptions = [ "--restart=unless-stopped" ];
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir}/configs 0750 root root -"
        "d ${cfg.dataDir}/icons   0750 root root -"
        "d ${cfg.dataDir}/data    0750 root root -"
      ];

      modules.services.vHosts.hosts.${cfg.domain} = {
        reverseProxyPort = cfg.port;
        displayName = "Home";
        category = "infrastructure";
        monitor = false;
      };
    })

    # ── Sync this host's vHosts into the central Homarr ──────────────────────
    (mkIf cfg.sync.enable {
      systemd.services.vHost-dashboard-homarr = {
        description = "Sync vHost service list to Homarr dashboard";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "agenix.service" ];
        wants = [ "network-online.target" "agenix.service" ];
        restartIfChanged = true;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "${pkgs.bash}/bin/bash -c 'i=0; until ${pkgs.curl}/bin/curl -sf ${cfg.sync.url}/api/ping > /dev/null 2>&1; do i=$((i+1)); [ $i -ge 60 ] && echo \"homarr-sync: timed out\" >&2 && exit 1; sleep 1; done'";
          ExecStart = "${homarrSyncScript}";
        };
      };
    })
  ];
}
