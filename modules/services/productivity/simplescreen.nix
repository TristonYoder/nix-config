# Wrapper for the external simplescreen flake (TristonYoder/simplescreen),
# which owns the Rust server and the services.simplescreen NixOS module.
# Imported directly in flake.nix for david, like b1church.nix.
#
# Data stays at the module default (/var/lib/private/simplescreen, DynamicUser).
# A dataDir elsewhere would need a pre-created directory the dynamic UID can
# write, which the upstream module doesn't handle. Back up db.sqlite and
# blobs/ together; the DB is WAL, so stop the service or use sqlite3 .backup.
#
# Exposure: Caddy only, bound to loopback. Apple ATS needs HTTPS for a
# non-.local name. Bonjour is off because it would advertise the loopback
# port; clients enter https://simplescreen.7co.dev by hand.
{ config, lib, ... }:

with lib;

let
  cfg = config.services.simplescreen;
  domain = "simplescreen.7co.dev";
in
{
  config = mkIf cfg.enable {
    services.simplescreen = {
      bind = mkDefault "127.0.0.1";
      openFirewall = mkDefault false;
      bonjour = mkDefault false;
      bootstrapTokenFile = config.age.secrets.simplescreen-bootstrap-token.path;
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
