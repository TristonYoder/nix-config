{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.infrastructure.dnsSync;
in
{
  options.modules.services.infrastructure.dnsSync = {
    enable = mkEnableOption "Auto-register vHost DNS records in Technitium on rebuild";

    technitiumUrl = mkOption {
      type = types.str;
      default = "http://localhost:5380";
      description = "Technitium DNS Server API base URL";
    };

    technitiumTokenFile = mkOption {
      type = types.path;
      default = config.age.secrets.technitium-api-token.path;
      description = "Path to file containing the Technitium API token";
    };

    zone = mkOption {
      type = types.str;
      default = config.networking.domain;
      description = "Primary DNS zone (e.g. theyoder.family)";
    };

    targetFqdn = mkOption {
      type = types.str;
      default = "${config.networking.hostName}.${config.networking.domain}";
      description = "CNAME target — this host's own FQDN";
    };

    stateFile = mkOption {
      type = types.str;
      default = "/var/lib/dns-sync/registered-records";
      description = "State file tracking registered DNS records for declarative cleanup";
    };

    cloudflare = {
      enable = mkEnableOption "Cloudflare tunnel route sync for public vHosts (Level 3)";

      apiTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing the Cloudflare API token (needs Tunnel:Edit permission)";
      };

      tunnelId = mkOption {
        type = types.str;
        default = "";
        description = "Cloudflare tunnel UUID";
      };

      accountId = mkOption {
        type = types.str;
        default = "";
        description = "Cloudflare account ID";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      # Collect vHosts from service modules — filter to DNS-enabled, active hosts
      allVHosts = filter (h: h.enable && h.dnsRecord) (attrValues config.modules.services.vHosts);
      internalDomains = map (h: h.virtualHost) (filter (h: !h.public) allVHosts);
      publicDomains   = map (h: h.virtualHost) (filter (h:  h.public) allVHosts);
      allDomains      = map (h: h.virtualHost) allVHosts;

      # Generate a bash array body from a list of domain strings
      toBashArray = domains:
        if domains == []
        then ""
        else concatStringsSep "\n" (map (d: "  \"${d}\"") domains);

      dnsSyncScript = pkgs.writeShellScript "dns-sync" ''
        set -eo pipefail

        TECHNITIUM_URL="${cfg.technitiumUrl}"
        TOKEN=$(cat "${cfg.technitiumTokenFile}")
        TARGET="${cfg.targetFqdn}"
        STATE_FILE="${cfg.stateFile}"
        CURL="${pkgs.curl}/bin/curl"
        JQ="${pkgs.jq}/bin/jq"

        # Strip first label to infer zone (baby.theyoder.family -> theyoder.family)
        get_zone() { echo "''${1#*.}"; }

        COMMENT="Managed by vHost on ${cfg.targetFqdn}"

        technitium_add() {
          local domain="$1" zone
          zone=$(get_zone "$domain")
          echo "  + $domain"
          $CURL --retry 5 --retry-delay 3 --retry-connrefused -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "domain=$domain" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=CNAME" \
            --data-urlencode "cname=$TARGET" \
            --data-urlencode "overwrite=true" \
            --data-urlencode "comments=$COMMENT" \
            "$TECHNITIUM_URL/api/zones/records/add" \
            | $JQ -r 'if .status == "ok" then "    ok" else "    error: \(.errorMessage)" end' || true
        }

        technitium_delete() {
          local domain="$1" zone
          zone=$(get_zone "$domain")
          echo "  - $domain (stale)"
          $CURL --retry 3 --retry-delay 2 -sf \
            "$TECHNITIUM_URL/api/zones/records/delete?token=$TOKEN&domain=$domain&zone=$zone&type=CNAME" \
            | $JQ -r 'if .status == "ok" then "    removed" else "    error: \(.errorMessage)" end' || true
        }

        # --- Domain lists baked in at build time ---

        INTERNAL_DOMAINS=(
        ${toBashArray internalDomains}
        )

        PUBLIC_DOMAINS=(
        ${toBashArray publicDomains}
        )

        ALL_DOMAINS=()
        for d in "''${INTERNAL_DOMAINS[@]-}"; do [ -n "$d" ] && ALL_DOMAINS+=("$d"); done
        for d in "''${PUBLIC_DOMAINS[@]-}" ; do [ -n "$d" ] && ALL_DOMAINS+=("$d"); done

        # --- Level 1: Register CNAMEs in Technitium ---

        echo "=== dns-sync: registering records -> $TARGET ==="
        for d in "''${ALL_DOMAINS[@]-}"; do
          [ -n "$d" ] && technitium_add "$d"
        done

        # --- Level 2: Declarative removal of stale records ---

        mkdir -p "$(dirname "$STATE_FILE")"
        if [ -f "$STATE_FILE" ]; then
          echo "=== dns-sync: checking for stale records ==="
          while IFS= read -r d; do
            [ -z "$d" ] && continue
            if ! printf '%s\n' "''${ALL_DOMAINS[@]-}" | grep -qxF "$d"; then
              technitium_delete "$d"
            fi
          done < "$STATE_FILE"
        fi
        printf '%s\n' "''${ALL_DOMAINS[@]-}" > "$STATE_FILE"

        ${optionalString cfg.cloudflare.enable ''
        # --- Level 3: Cloudflare tunnel routes for public vHosts ---

        echo "=== dns-sync: syncing Cloudflare tunnel routes ==="
        CF_TOKEN=$(cat "$CF_TOKEN_FILE")

        PUBLIC_DOMAINS_JSON=$(printf '%s\n' "''${PUBLIC_DOMAINS[@]-}" \
          | grep -v '^$' \
          | ${pkgs.jq}/bin/jq -Rs '[split("\n")[] | select(. != "")]')

        INGRESS_JSON=$(${pkgs.jq}/bin/jq -n \
          --argjson domains "$PUBLIC_DOMAINS_JSON" \
          '[ $domains[] | { hostname: ., service: "https://localhost:443", originRequest: { noTLSVerify: true } } ]
           + [{ service: "http_status:404" }]')

        $CURL -sf -X PUT \
          "https://api.cloudflare.com/client/v4/accounts/${cfg.cloudflare.accountId}/cfd_tunnel/${cfg.cloudflare.tunnelId}/configurations" \
          -H "Authorization: Bearer $CF_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"config\": {\"ingress\": $INGRESS_JSON}}" \
          | ${pkgs.jq}/bin/jq -r 'if .success then "  Cloudflare tunnel updated." else "  Cloudflare error: \(.errors)" end'
        ''}

        echo "=== dns-sync: complete ==="
      '';
    in
    {
      systemd.services.dns-sync = {
        description = "Sync vHost DNS records to Technitium";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "agenix.service" "technitium-dns-server.service" ];
        wants = [ "network-online.target" "agenix.service" ];
        restartIfChanged = true;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${dnsSyncScript}";
          StateDirectory = "dns-sync";
        } // optionalAttrs cfg.cloudflare.enable {
          Environment = [ "CF_TOKEN_FILE=${toString cfg.cloudflare.apiTokenFile}" ];
        };
      };
    }
  );
}
