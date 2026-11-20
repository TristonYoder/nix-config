# Wrapper for the external simplescreen flake (TristonYoder/simplescreen),
# which owns the Rust server and the services.simplescreen NixOS module.
# Imported directly in flake.nix for david, like b1church.nix.
#
# Data stays at the module default (/var/lib/private/simplescreen, DynamicUser).
# A dataDir elsewhere would need a pre-created directory the dynamic UID can
# write, which the upstream module doesn't handle. Back up db.sqlite and
# blobs/ together; the DB is WAL, so stop the service or use sqlite3 .backup.
#
# Exposure: https://simplescreen.7co.dev through Caddy, plus the plain port on
# the LAN for Bonjour. The server's own mDNS responder advertises
# simplescreen-<id>.local:8420 (plain http is fine for .local under Apple ATS).
# HOSTNAME stays unset so it doesn't claim david.local, which avahi owns.
{ config, lib, ... }:

with lib;

let
  cfg = config.services.simplescreen;
  domain = "simplescreen.7co.dev";
in
{
  config = mkIf cfg.enable {
    services.simplescreen = {
      bind = mkDefault "0.0.0.0";
      # TCP 8420 and UDP 5353 (5353 is already open for avahi).
      openFirewall = mkDefault true;
      bonjour = mkDefault true;
      # Break-glass admin; day-to-day sign-in is OIDC below.
      bootstrapTokenFile = config.age.secrets.simplescreen-bootstrap-token.path;

      # Pocket ID public client "simplescreen" (PKCE, redirect
      # simplescreen://oauth/callback), restricted to the simplescreen_admin
      # and simplescreen_editor groups. Bind simplescreen_editor (or any
      # other group) to a Simple Screen group in Studio to grant access.
      # id_token, not access_token: the ID token is where Pocket ID carries the
      # groups claim. Issuer has no trailing slash and must match iss exactly.
      oidc = {
        issuer = mkDefault "https://id.${config.networking.domain}";
        clientId = mkDefault "simplescreen";
        adminGroups = mkDefault [ "simplescreen_admin" ];
        tokenType = mkDefault "id_token";
      };
    };

    # Caddy proxies WebSockets (/v1/ws) and streams request bodies without a
    # size limit or read timeout by default, and the Caddy provider adds no
    # encode directive, so multi-GB PUT /v1/blobs/* uploads, the 20 s WS
    # pings, and Range / ETag headers all pass through untouched.
    modules.services.vHosts.hosts.${domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Simple Screen";
      category = "productivity";
      icon = "apple-tv";
    };
  };
}
