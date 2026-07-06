{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.providers.dns-technitium;
in
{
  options.modules.services.providers.dns-technitium = {
    enable = mkEnableOption "Auto-register vHost DNS records in Technitium on rebuild";

    url = mkOption {
      type = types.str;
      default = "http://localhost:5380";
      description = "Technitium DNS Server API base URL";
    };

    tokenFile = mkOption {
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

  config = mkIf cfg.enable (
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
      allVHosts       = filter (h: h.enable && h.dnsRecord) (attrValues config.modules.services.vHosts.hosts);
      cnameVHosts     = filter (h: h.ipAddress == null) allVHosts;
      aRecordVHosts   = filter (h: h.ipAddress != null) allVHosts;

      internalDomains = concatMap (h: normalizeDomains h.virtualHost ++ h.serverAliases) (filter (h: !h.public) cnameVHosts);
      publicDomains   = concatMap (h: normalizeDomains h.virtualHost ++ h.serverAliases) (filter (h:  h.public) cnameVHosts);
      allDomains      = internalDomains ++ publicDomains;

      # domain|ip pairs for vHosts that point directly at an external IP
      aRecordEntries  = concatMap
        (h: map (d: "${d}|${h.ipAddress}") (normalizeDomains h.virtualHost ++ h.serverAliases))
        aRecordVHosts;

      # Generate a bash array body from a list of domain strings
      toBashArray = domains:
        if domains == []
        then ""
        else concatStringsSep "\n" (map (d: "  \"${d}\"") domains);

      dnsSyncScript = pkgs.writeShellScript "dns-sync" ''
        set -eo pipefail

        TECHNITIUM_URL="${cfg.url}"
        TOKEN=$(cat "${cfg.tokenFile}")
        TARGET="${cfg.targetFqdn}"
        STATE_FILE="${cfg.stateFile}"
        CURL="${pkgs.curl}/bin/curl"
        JQ="${pkgs.jq}/bin/jq"

        COMMENT="Managed by vHost on ${cfg.targetFqdn}"

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
          echo "    creating forwarder zone: $zone -> 1.1.1.1" >&2
          $CURL -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=Forwarder" \
            --data-urlencode "forwarder=1.1.1.1" \
            "$TECHNITIUM_URL/api/zones/create" | $JQ -r '.status' >&2 || true
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

        technitium_add_a() {
          local domain="$1" ip="$2" zone
          zone=$(find_zone "$domain")
          if [ -z "$zone" ]; then
            echo "  + $domain -> $ip (no zone found — creating)"
            zone=$(create_zone "$domain")
          else
            echo "  + $domain -> $ip"
          fi
          $CURL --retry 5 --retry-delay 3 --retry-connrefused -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "domain=$domain" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=A" \
            --data-urlencode "ipAddress=$ip" \
            --data-urlencode "overwrite=true" \
            --data-urlencode "comments=$COMMENT" \
            "$TECHNITIUM_URL/api/zones/records/add" \
            | $JQ -r 'if .status == "ok" then "    ok (A)" else "    error: \(.errorMessage)" end' || true
        }

        technitium_delete_a() {
          local domain="$1" zone
          zone=$(find_zone "$domain")
          [ -z "$zone" ] && return
          echo "  - $domain (stale A record)"
          $CURL --retry 3 --retry-delay 2 -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "domain=$domain" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=A" \
            "$TECHNITIUM_URL/api/zones/records/delete" \
            | $JQ -r 'if .status == "ok" then "    removed" else "    error: \(.errorMessage)" end' || true
        }

        technitium_delete() {
          local domain="$1" zone record_type
          zone=$(find_zone "$domain")
          [ -z "$zone" ] && return
          echo "  - $domain (stale)"
          # Use ANAME at zone apex (mirrors technitium_add logic), CNAME elsewhere
          if [ "$domain" = "$zone" ]; then
            record_type="ANAME"
          else
            record_type="CNAME"
          fi
          $CURL --retry 3 --retry-delay 2 -sfG \
            --data-urlencode "token=$TOKEN" \
            --data-urlencode "domain=$domain" \
            --data-urlencode "zone=$zone" \
            --data-urlencode "type=$record_type" \
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

        # "domain|ip" pairs for vHosts pointing directly at an external IP
        A_RECORD_PAIRS=(
        ${toBashArray aRecordEntries}
        )

        ALL_DOMAINS=()
        for d in "''${INTERNAL_DOMAINS[@]-}"; do [ -n "$d" ] && ALL_DOMAINS+=("$d"); done
        for d in "''${PUBLIC_DOMAINS[@]-}" ; do [ -n "$d" ] && ALL_DOMAINS+=("$d"); done

        # "domain|kind" entries actually registered this run, for stale-cleanup diffing
        REGISTERED=()

        # --- Level 1: Register CNAME/ANAME records in Technitium ---

        echo "=== dns-sync: registering records -> $TARGET ==="
        for d in "''${ALL_DOMAINS[@]-}"; do
          [ -z "$d" ] && continue
          technitium_add "$d"
          REGISTERED+=("$d|cname")
        done

        # --- Level 1b: Register direct A records ---

        echo "=== dns-sync: registering direct A records ==="
        for pair in "''${A_RECORD_PAIRS[@]-}"; do
          [ -z "$pair" ] && continue
          domain="''${pair%%|*}"
          ip="''${pair#*|}"
          technitium_add_a "$domain" "$ip"
          REGISTERED+=("$domain|a")
        done

        # --- Level 2: Declarative removal of stale records ---

        mkdir -p "$(dirname "$STATE_FILE")"
        if [ -f "$STATE_FILE" ]; then
          echo "=== dns-sync: checking for stale records ==="
          while IFS= read -r line; do
            [ -z "$line" ] && continue
            domain="''${line%%|*}"
            kind="''${line#*|}"
            # legacy state file entries have no "|kind" suffix — they're all cname
            [ "$kind" = "$line" ] && kind="cname"
            if ! printf '%s\n' "''${REGISTERED[@]-}" | grep -qxF "$domain|$kind"; then
              if [ "$kind" = "a" ]; then
                technitium_delete_a "$domain"
              else
                technitium_delete "$domain"
              fi
            fi
          done < "$STATE_FILE"
        fi
        printf '%s\n' "''${REGISTERED[@]-}" > "$STATE_FILE"

        echo "=== dns-sync: complete ==="
      '';
    in
    {
      systemd.services.vHost-dns-technitium = {
        description = "Sync vHost DNS records to Technitium";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "agenix.service" "technitium-dns-server.service" ];
        wants = [ "network-online.target" "agenix.service" "technitium-dns-server.service" ];
        restartIfChanged = true;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Wait for Technitium's HTTP listener before running dns-sync.
          # Technitium may still be starting when activation triggers this unit.
          ExecStartPre = "${pkgs.bash}/bin/bash -c 'i=0; until ${pkgs.curl}/bin/curl -sf http://localhost:5380/api/status > /dev/null 2>&1; do i=$((i+1)); [ $i -ge 60 ] && echo \"dns-sync: timed out waiting for Technitium\" >&2 && exit 1; sleep 1; done'";
          ExecStart = "${dnsSyncScript}";
          StateDirectory = "dns-sync";
        };
      };
    }
  );
}
