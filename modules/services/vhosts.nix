{ config, lib, ... }:

with lib;

let
  # Auto-expand a bare subdomain (no dots) to a FQDN using networking.domain.
  # Keys that already contain dots are used verbatim for backward compat.
  expandDomain = name:
    if (builtins.match ".*\\..*" name) != null
    then name
    else "${name}.${config.networking.domain}";

  # Title-case a string: "budget" → "Budget", "open-webui" → "Open-webui"
  titleCase = s:
    let first = lib.toUpper (lib.substring 0 1 s);
        rest  = lib.substring 1 (lib.stringLength s - 1) s;
    in "${first}${rest}";
in
{
  config = {
    # Add /etc/hosts entries for all registered vHosts so services on this
    # machine can resolve local domains without needing Technitium as the
    # system resolver (david uses 1.1.1.1; Technitium only handles external clients).
    networking.hosts."127.0.0.1" =
      map (h: h.virtualHost)
        (filter (h: h.enable)
          (attrValues config.modules.services.vHosts.hosts));
  };

  options.modules.services.vHosts = {
    hosts = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to create this virtual host.";
          };

          virtualHost = mkOption {
            type = types.str;
            default = expandDomain name;
            description = ''
              FQDN for this virtual host.
              Defaults to the attribute key if it contains dots; otherwise
              auto-expands to ''${key}.''${networking.domain}.
            '';
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

          rawConfig = mkOption {
            type = types.bool;
            default = false;
            description = "When true, extraConfig is output verbatim inside the site block. The managed reverse proxy template is skipped; caller is responsible for all routing directives.";
          };

          public = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether the virtual host is publicly accessible.
              When true and the cloudflare-tunnel provider is enabled, an
              ingress rule is added to route this domain through the tunnel.
            '';
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
            description = "Additional config for this virtual host. In managed mode, appended after the proxy directive. In rawConfig mode, this is the entire site block content.";
          };

          # ── Provider metadata (consumed by dashboard / monitoring providers) ──

          displayName = mkOption {
            type = types.str;
            default = titleCase name;
            description = "Human-readable service name shown in dashboards.";
          };

          category = mkOption {
            type = types.str;
            default = "";
            description = "Dashboard category (e.g. \"media\", \"productivity\", \"infrastructure\").";
          };

          icon = mkOption {
            type = types.str;
            default = "";
            description = "Icon identifier or URL used by the dashboard provider.";
          };

          monitor = mkOption {
            type = types.bool;
            default = true;
            description = "Whether the monitoring provider should track uptime for this host.";
          };
        };
      }));
      default = { };
      description = ''
        Agnostic virtual host registry consumed by all provider modules
        (reverse proxy, DNS, Cloudflare tunnel, dashboard, monitoring).

        Minimal declaration — bare subdomain, auto-expands to FQDN:

          modules.services.vHosts.hosts."budget" = {
            reverseProxyPort = cfg.port;
          };
          # → virtualHost = "budget.''${networking.domain}"
          # → displayName  = "Budget"
          # → Caddy + Technitium DNS wired automatically (if enabled)

        Public exposure via Cloudflare tunnel:

          modules.services.vHosts.hosts."budget" = {
            reverseProxyPort = cfg.port;
            public = true;
          };
      '';
    };
  };
}
