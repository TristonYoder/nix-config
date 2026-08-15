# Wrapper for the external b1church flake (TristonYoder/b1church), which owns
# the containers, storage and snapshots for the self-hosted ChurchApps stack.
#
# The split follows modules/services/ai/hermes-agent.nix: the upstream module
# stays evaluable on its own by stopping at loopback ports, and this file adds
# the pieces that are specific to this repo — vHosts registration and agenix
# secret paths.
#
# Like hermes, this is imported directly in flake.nix for david rather than via
# modules/services/productivity/default.nix, so hosts that don't use it (and
# pits, which can't always reach github) never pull the input.
#
# Public exposure: david's cloudflared is token-based and remotely managed
# (profiles/server.nix), so the hostname → tunnel mapping lives in the
# Cloudflare Zero Trust dashboard, not here — same as plotiphar.com itself
# (docker/productivity/stageplotiphar.nix). Enabling this gets Caddy serving;
# the dashboard routes still have to be added.
{ config, lib, ... }:

with lib;

let
  cfg = config.services.b1church;
in
{
  config = mkIf cfg.enable {
    # Secrets stay in this repo — they're encrypted to david's host key and
    # managed by agenix here, so the external module takes them as paths.
    services.b1church = {
      dbSecretFile = config.age.secrets.b1church-db-secrets.path;
      apiSecretFile = config.age.secrets.b1church-api-secrets.path;
      # On david's ZFS pool, so it inherits the pool snapshot policy. Mode
      # 0700 root:root — /data/docker-appdata is NFS-exported without
      # no_root_squash, so a remote root maps to nobody.
      dataDir = mkDefault "/data/docker-appdata/b1church";
    };

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
        # which does its own client-side routing. The Api mounts every module
        # route relatively, so stripping the prefix is safe, and this keeps it
        # same-origin with the admin UI.
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

    # Wildcard vHost for the member portal. B1App resolves the church from the
    # host / x-site header (its next.config.mjs), so every church subdomain is
    # served by the one container. The wildcard cert needs DNS-01, so the
    # Cloudflare API token must cover this zone.
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
  };
}
