{ config, lib, pkgs, blueprint, ... }:

with lib;
let
  cfg = config.modules.services.productivity.blueprint;

  # blueprint's own flake.nix owns the buildNpmPackage derivation (source,
  # npmDepsHash, standalone installPhase) — this module just consumes the
  # package output and wires it into systemd/postgres/vHosts, same pattern
  # as iopodcli's overlay in modules/services/storage/ipod-sync.nix.
  blueprintPkg = blueprint.packages.${pkgs.system}.default;
in
{
  options.modules.services.productivity.blueprint = {
    enable = mkEnableOption "Blueprint personal dashboard";

    domain = mkOption {
      type = types.str;
      default = "blueprint.${config.networking.domain}";
      description = "Domain for Blueprint";
    };

    port = mkOption {
      type = types.port;
      default = 3212;
      description = "Port Blueprint's Next.js server listens on";
    };

    user = mkOption {
      type = types.str;
      default = "blueprint";
      description = "System user Blueprint runs as, and its Postgres role/database name";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      description = "Blueprint service user";
    };
    users.groups.${cfg.user} = { };

    # Peer-auth over the Unix socket against the shared instance, matching
    # this repo's only other example (matrix-synapse) — no password/secret
    # needed since the systemd service runs as this same-named role.
    services.postgresql = {
      ensureUsers = [
        {
          name = cfg.user;
          ensureDBOwnership = true;
        }
      ];
      ensureDatabases = [ cfg.user ];
    };

    systemd.services.blueprint = {
      description = "Blueprint personal dashboard";
      after = [ "network.target" "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NODE_ENV = "production";
        PORT = toString cfg.port;
        HOSTNAME = "127.0.0.1";
        DATABASE_URL = "postgresql:///${cfg.user}?host=/run/postgresql";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = "${pkgs.nodejs_22}/bin/node ${blueprintPkg}/server.js";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Not automated yet: `drizzle-kit migrate` is a build-time devDependency,
    # not part of the standalone runtime output, so there's no migration
    # runner wired into the service start. Run it manually after first
    # deploy and after any future schema change, from a checkout with
    # node_modules (the systemd unit's own build output doesn't carry
    # drizzle-kit itself):
    #   DATABASE_URL="postgresql:///blueprint?host=/run/postgresql" \
    #     sudo -u blueprint npx drizzle-kit migrate

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Blueprint";
      category = "productivity";
    };
  };
}
