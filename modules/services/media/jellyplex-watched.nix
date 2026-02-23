{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.jellyplexWatched;
  plexCfg = config.modules.services.media.plex;
  jellyfinCfg = config.modules.services.media.jellyfin;

  boolStr = value: if value then "True" else "False";

  pythonEnv = pkgs.python312.withPackages (ps: [
    ps.loguru
    ps.packaging
    ps.plexapi
    ps.pydantic
    ps."python-dotenv"
    ps.requests
  ]);

  src = pkgs.fetchFromGitHub {
    owner = "luigi311";
    repo = "JellyPlex-Watched";
    rev = "ee769a518a877a752ad89adc3f87424059a69125";
    sha256 = "sha256-C8Me23RM/Ct/JiDdCSm/TLrm6djpo8FNbeUkSJMt/iE=";
  };

  extraEnvLines =
    concatStringsSep "\n"
      (mapAttrsToList (key: value: "${key}=${escapeShellArg value}") cfg.extraEnv);

  envPath = "/run/jellyplex-watched/jellyplex.env";
in
{
  options.modules.services.media.jellyplexWatched = {
    enable = mkEnableOption "JellyPlex-Watched sync";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/jellyplex-watched";
      description = "Directory for JellyPlex-Watched logs and state";
    };

    user = mkOption {
      type = types.str;
      default = "jellyplex-watched";
      description = "User account for JellyPlex-Watched";
    };

    group = mkOption {
      type = types.str;
      default = "jellyplex-watched";
      description = "Group for JellyPlex-Watched";
    };

    python = mkOption {
      type = types.package;
      default = pythonEnv;
      description = "Python environment with JellyPlex-Watched dependencies";
    };

    source = mkOption {
      type = types.path;
      default = src;
      description = "JellyPlex-Watched source";
    };

    plexBaseUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:${toString plexCfg.port}";
      description = "Plex base URL";
    };

    jellyfinBaseUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:${toString jellyfinCfg.port}";
      description = "Jellyfin base URL";
    };

    plexTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Plex token";
    };

    jellyfinTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Jellyfin token";
    };

    dryRun = mkOption {
      type = types.bool;
      default = false;
      description = "Log actions without updating watch status";
    };

    debugLevel = mkOption {
      type = types.str;
      default = "INFO";
      description = "Logging level (INFO or DEBUG)";
    };

    sleepDuration = mkOption {
      type = types.ints.positive;
      default = 3600;
      description = "Sync interval in seconds";
    };

    requestTimeout = mkOption {
      type = types.ints.positive;
      default = 300;
      description = "HTTP request timeout in seconds";
    };

    maxThreads = mkOption {
      type = types.ints.positive;
      default = 1;
      description = "Max worker threads for processing";
    };

    generateGuids = mkOption {
      type = types.bool;
      default = true;
      description = "Generate GUIDs when matching items";
    };

    generateLocations = mkOption {
      type = types.bool;
      default = true;
      description = "Generate file locations when matching items";
    };

    syncFromPlexToJellyfin = mkOption {
      type = types.bool;
      default = true;
      description = "Sync watched status from Plex to Jellyfin";
    };

    syncFromJellyfinToPlex = mkOption {
      type = types.bool;
      default = true;
      description = "Sync watched status from Jellyfin to Plex";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional .env entries for JellyPlex-Watched";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = plexCfg.enable;
        message = "jellyplexWatched requires modules.services.media.plex.enable = true";
      }
      {
        assertion = jellyfinCfg.enable;
        message = "jellyplexWatched requires modules.services.media.jellyfin.enable = true";
      }
      {
        assertion = cfg.plexTokenFile != null;
        message = "jellyplexWatched requires modules.services.media.jellyplexWatched.plexTokenFile";
      }
      {
        assertion = cfg.jellyfinTokenFile != null;
        message = "jellyplexWatched requires modules.services.media.jellyplexWatched.jellyfinTokenFile";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = false;
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d /run/jellyplex-watched 0750 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.jellyplex-watched = {
      description = "JellyPlex-Watched sync service";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = {
        ENV_FILE = envPath;
      };

      preStart = ''
        PLEX_TOKEN=$(cat ${cfg.plexTokenFile})
        JELLYFIN_TOKEN=$(cat ${cfg.jellyfinTokenFile})

        cat > ${envPath} <<EOF
DRYRUN="${boolStr cfg.dryRun}"
DEBUG_LEVEL="${cfg.debugLevel}"
RUN_ONLY_ONCE="False"
SLEEP_DURATION="${toString cfg.sleepDuration}"
LOG_FILE="${cfg.dataDir}/jellyplex-watched.log"
MARK_FILE="${cfg.dataDir}/jellyplex-watched.mark"
REQUEST_TIMEOUT="${toString cfg.requestTimeout}"
MAX_THREADS="${toString cfg.maxThreads}"
GENERATE_GUIDS="${boolStr cfg.generateGuids}"
GENERATE_LOCATIONS="${boolStr cfg.generateLocations}"
PLEX_BASEURL="${cfg.plexBaseUrl}"
PLEX_TOKEN="$PLEX_TOKEN"
JELLYFIN_BASEURL="${cfg.jellyfinBaseUrl}"
JELLYFIN_TOKEN="$JELLYFIN_TOKEN"
SYNC_FROM_PLEX_TO_JELLYFIN="${boolStr cfg.syncFromPlexToJellyfin}"
SYNC_FROM_PLEX_TO_PLEX="False"
SYNC_FROM_PLEX_TO_EMBY="False"
SYNC_FROM_JELLYFIN_TO_PLEX="${boolStr cfg.syncFromJellyfinToPlex}"
SYNC_FROM_JELLYFIN_TO_JELLYFIN="False"
SYNC_FROM_JELLYFIN_TO_EMBY="False"
SYNC_FROM_EMBY_TO_PLEX="False"
SYNC_FROM_EMBY_TO_JELLYFIN="False"
SYNC_FROM_EMBY_TO_EMBY="False"
${extraEnvLines}
EOF

        chown ${cfg.user}:${cfg.group} ${envPath}
        chmod 600 ${envPath}
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.python}/bin/python ${cfg.source}/main.py";
        Restart = "on-failure";
        RestartSec = "10s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir "/run/jellyplex-watched" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        LockPersonality = true;
      };
    };
  };
}
