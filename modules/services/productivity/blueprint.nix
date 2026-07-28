{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.productivity.blueprint;
  unstable = import nixpkgs-unstable { system = pkgs.system; };

  # No buildNpmPackage precedent exists anywhere else in this repo (grepped
  # the whole tree) — this is the first native (non-Docker) Next.js
  # deployment here. Builds the "standalone" server.js output the same way
  # Blueprint's own Dockerfile does, just without the container layer.
  blueprint = pkgs.buildNpmPackage {
    pname = "blueprint";
    version = cfg.rev;
    src = pkgs.fetchFromGitHub {
      owner = "TristonYoder";
      repo = "blueprint";
      rev = cfg.rev;
      hash = cfg.srcHash;
    };

    npmDepsHash = cfg.npmDepsHash;
    nodejs = unstable.nodejs_22;
    npmBuildScript = "build";

    # DATABASE_URL only needs to resolve at runtime, not build time — `next
    # build` doesn't touch the DB (every route is force-dynamic) — but the
    # Postgres client library still wants *a* well-formed value present to
    # construct its Pool without throwing at import time during the build.
    DATABASE_URL = "postgresql://build:build@localhost/build";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r .next/standalone/. $out/
      mkdir -p $out/.next
      cp -r .next/static $out/.next/static
      cp -r public $out/public
      runHook postInstall
    '';
  };
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

    rev = mkOption {
      type = types.str;
      default = "fe6a98f61c1c13701a4276327319b9f15c298ec4";
      description = "Git rev of TristonYoder/blueprint (public) to build";
    };

    srcHash = mkOption {
      type = types.str;
      default = "sha256-VxpeHdvY7AuG1Sf+t4T1hS4JxHqUrlg/Q20SNrmI/qs=";
      description = "Output hash of the fetched source tree at `rev`";
    };

    npmDepsHash = mkOption {
      type = types.str;
      default = "sha256-FLKyt0DSr1dboOdE3dhx5fsaCUfW+4SC2EmZ6cY2GUg=";
      description = "npm dependency hash for buildNpmPackage";
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
        ExecStart = "${unstable.nodejs_22}/bin/node ${blueprint}/server.js";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Not automated yet: `drizzle-kit migrate` is a build-time devDependency,
    # not part of the standalone runtime output, so there's no migration
    # runner wired into the service start. Run it manually after first
    # deploy and after any future schema change:
    #   DATABASE_URL="postgresql:///blueprint?host=/run/postgresql" \
    #     sudo -u blueprint npx drizzle-kit migrate
    # (from a checkout with node_modules — the systemd unit's own build
    # output doesn't carry drizzle-kit itself).

    modules.services.vHosts.hosts."blueprint" = {
      reverseProxyPort = cfg.port;
      displayName = "Blueprint";
      category = "productivity";
    };
  };
}
