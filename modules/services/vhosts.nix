{ config, lib, pkgs, ... }:

with lib;

let
  dnsSync = config.modules.services.infrastructure.dnsSync;
in
{
  options = {
    modules.services.vHosts = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to create this virtual host.";
          };

          virtualHost = mkOption {
            type = types.str;
            default = name;
            description = "Virtual host name (defaults to the attribute key).";
          };

          reverseProxyAddress = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Explicit upstream reverse proxy target (overrides host/port/SSL if set).";
          };

          reverseProxyHost = mkOption {
            type = types.str;
            default = "localhost";
            description = "Reverse proxy host (defaults to the local machine).";
          };

          reverseProxyPort = mkOption {
            type = types.port;
            default = 80;
            description = "Reverse proxy port.";
          };

          reverseProxySSL = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to use HTTPS when building the reverse proxy address.";
          };

          managedProxy = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to use the managed reverse proxy template.";
          };

          public = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the virtual host should be publicly accessible.";
          };

          dnsRecord = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to include this virtual host in managed DNS records.";
          };

          dnsChallenge = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable DNS-01 TLS for this host (provider-specific in proxy module).";
          };

          serverAliases = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional hostnames served by this virtual host.";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional reverse proxy config appended to this virtual host.";
          };
        };
      }));
      default = { };
      description = "Agnostic virtual host definitions used by reverse proxy and DNS sync modules.";
    };

    modules.services.infrastructure.dnsSync = {
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
    };
  };

  config = mkIf dnsSync.enable (
    let
      # Normalize a raw virtualHost string into a list of valid DNS names:
      # - strips http:// / https:// prefixes
      # - splits on whitespace (Caddy multi-domain syntax)
      # - drops empty strings
      normalizeDomains = vhost:
        let
          stripped = removePrefix "https://" (removePrefix "http://" vhost);
          parts    = splitString " " stripped;
        in filter (s: s != "") parts;

      # Collect vHosts from service modules — filter to DNS-enabled, active hosts
      # Include serverAliases so every domain served gets a record
      allVHosts       = filter (h: h.enable && h.dnsRecord) (attrValues config.modules.services.vHosts);
      internalDomains = concatMap (h: normalizeDomains h.virtualHost ++ h.serverAliases) (filter (h: !h.public) allVHosts);
      publicDomains   = concatMap (h: normalizeDomains h.virtualHost ++ h.serverAliases) (filter (h:  h.public) allVHosts);
      allDomains      = internalDomains ++ publicDomains;

      # Generate a bash array body from a list of domain strings
      toBashArray = domains:
        if domains == []
        then ""
        else concatStringsSep "\n" (map (d: "  \"${d}\"") domains);

      dnsSyncScript = pkgs.writeShellScript "dns-sync" ''
        set -eo pipefail

        TECHNITIUM_URL="${dnsSync.technitiumUrl}"
        TOKEN=$(cat "${dnsSync.technitiumTokenFile}")
        TARGET="${dnsSync.targetFqdn}"
        STATE_FILE="${dnsSync.stateFile}"
        CURL="${pkgs.curl}/bin/curl"
        JQ="${pkgs.jq}/bin/jq"

        COMMENT="Managed by vHost on ${dnsSync.targetFqdn}"

        # Fetch all known zones from Technitium, sorted longest-first for best-match lookup
        refresh_zones() {
          ZONE_LIST=$($CURL -sfG \
            --data-urlencode "token=$TOKEN" \
            "$TECHNITIUM_URL/api/zones/list" \
            | $JQ -r '[.response.zones[].name] | sort_by(length) | reverse | .[]')
        }
        refresh_zones

        # Find the longest existing zone that is a suffix of domain
        find_zone() {
          local domain="$1"
          while IFS= read -r zone; do
            if [[ "$domain" == "$zone" ]] || [[ "$domain" == *".$zone" ]]; then
              echo "$zone"
              return
            fi
          done <<< "$ZONE_LIST"
          echo ""
        }

        # Extract TLD+1 using pure bash (e.g. sub.foo.bar -> foo.bar)
        tld_plus_one() {
          local domain="$1"
          local IFS='.'
          read -ra labels <<< "$domain"
          local n=''${#labels[@]}
          if [ "$n" -ge 2 ]; then
            echo "''${labels[$((n-2))]}.''${labels[$((n-1))]}"
          else
            echo "$domain"
          fi
        }

        # Create a Forwarder zone (TLD+1 heuristic), forwarding to 1.1.1.1
        create_zone() {
          local domain="$1"
          local zone
          zone=$(tld_plus_one "$domain")
          echo "    creating forwarder zone: $zone -> 1.1.1.1"
          $CURL -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=Forwarder" \
            --data-urlencode "forwarder=1.1.1.1" \
            "$TECHNITIUM_URL/api/zones/create" | $JQ -r '.status' || true
          refresh_zones
          echo "$zone"
        }

        technitium_add() {
          local domain="$1" zone
          zone=$(find_zone "$domain")
          if [ -z "$zone" ]; then
            echo "  + $domain (no zone found — creating)"
            zone=$(create_zone "$domain")
          else
            echo "  + $domain"
          fi
          # At zone apex CNAME is forbidden by DNS RFC; use ANAME (alias) instead
          if [ "$domain" = "$zone" ]; then
            $CURL --retry 5 --retry-delay 3 --retry-connrefused -sfG \
              --data-urlencode "token=$TOKEN" \
              --data-urlencode "domain=$domain" \
              --data-urlencode "zone=$zone" \
              --data-urlencode "type=ANAME" \
              --data-urlencode "aname=$TARGET" \
              --data-urlencode "overwrite=true" \
              --data-urlencode "comments=$COMMENT" \
              "$TECHNITIUM_URL/api/zones/records/add" \
              | $JQ -r 'if .status == "ok" then "    ok (ANAME)" else "    error: \(.errorMessage)" end' || true
          else
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
          fi
        }

        technitium_delete() {
          local domain="$1" zone
          zone=$(find_zone "$domain")
          [ -z "$zone" ] && return
          echo "  - $domain (stale)"
          $CURL --retry 3 --retry-delay 2 -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "domain=$domain" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=CNAME" \
            "$TECHNITIUM_URL/api/zones/records/delete" \
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
        };
      };
    }
  );
}
