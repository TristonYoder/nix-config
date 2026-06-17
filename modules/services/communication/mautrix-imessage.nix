{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.mautrix-imessage;
  matrixCfg = config.modules.services.communication.matrix-synapse;
in
{
  options.modules.services.communication.mautrix-imessage = {
    enable = mkEnableOption "mautrix-imessage Matrix bridge with BlueBubbles";

    domain = mkOption {
      type = types.str;
      default = matrixCfg.serverName;
      description = "The domain name of your Matrix homeserver";
    };

    homeserverUrl = mkOption {
      type = types.str;
      default = "http://localhost:${toString matrixCfg.clientPort}";
      description = "URL where the homeserver can be reached";
    };

    port = mkOption {
      type = types.port;
      default = 29319;
      description = "Port for the bridge's appservice listener";
    };

    provisioningWhitelist = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "@admin:example.com" ];
      description = "List of Matrix user IDs allowed to use the bridge";
    };

    blueBubblesUrl = mkOption {
      type = types.str;
      example = "http://bluebubbles-server:1234";
      description = "URL of the BlueBubbles server";
    };

    blueBubblesPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/agenix/bluebubbles-password";
      description = ''
        Path to file containing the BlueBubbles server password.
        If null, blueBubblesPassword must be set (not recommended for production).
      '';
    };

    blueBubblesPassword = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Password for the BlueBubbles server.
        WARNING: This will be stored in plaintext in the Nix store.
        Use blueBubblesPasswordFile instead for production.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      dataDir = "/var/lib/mautrix-imessage";
      registrationFile = "${dataDir}/registration.yaml";

      passwordFile =
        if cfg.blueBubblesPasswordFile != null then
          cfg.blueBubblesPasswordFile
        else if cfg.blueBubblesPassword != null then
          null  # Will use plaintext password
        else
          config.age.secrets.bluebubbles-password.path;

      # Build the mautrix-imessage bridge from source
      mautrix-imessage = pkgs.buildGoModule rec {
        pname = "mautrix-imessage";
        version = "unstable-2024-10-15";

        src = pkgs.fetchFromGitHub {
          owner = "mautrix";
          repo = "imessage";
          rev = "master";
          sha256 = "sha256-jl53IbtPG0Fi/3zcAT6he62SJzCKP0NQS09pLWjrj/s=";
        };

        proxyVendor = true;
        vendorHash = "sha256-JXQ7S6Z/lG3vBeaiVUIr2LPyCrhKCN5pEIRSeFy6Lzk=";

        buildInputs = [ pkgs.olm ];

        subPackages = [ "." ];

        env.CGO_ENABLED = 1;

        meta = with lib; {
          description = "A Matrix-iMessage puppeting bridge";
          homepage = "https://github.com/mautrix/imessage";
          license = licenses.agpl3Plus;
        };
      };

      settingsFormat = pkgs.formats.yaml {};
      configFile = settingsFormat.generate "config.yaml" {
        homeserver = {
          address = cfg.homeserverUrl;
          domain = cfg.domain;
          websocket_proxy = null;
          software = "standard";
          async_media = false;
        };

        appservice = {
          hostname = "0.0.0.0";
          port = cfg.port;

          database = {
            type = "sqlite3-fk-wal";
            uri = "file:${dataDir}/mautrix-imessage.db?_txlock=immediate";
          };

          id = "imessage";
          bot = {
            username = "imessagebot";
            displayname = "iMessage Bridge Bot";
            avatar = "";
          };

          ephemeral_events = true;

          as_token = "generate";
          hs_token = "generate";
        };

        imessage = {
          platform = "bluebubbles";
          bluebubbles_url = cfg.blueBubblesUrl;
          bluebubbles_password = "BLUEBUBBLES_PASSWORD_PLACEHOLDER";
        };

        bridge = {
          user = if (builtins.length cfg.provisioningWhitelist) > 0
                 then builtins.head cfg.provisioningWhitelist
                 else "@you:example.com";

          username_template = "imessage_{{.}}";
          displayname_template = "{{.}}";

          permissions = lib.listToAttrs (map (user: {
            name = user;
            value = "admin";
          }) cfg.provisioningWhitelist);

          delivery_receipts = false;
          message_status_events = true;
          send_error_notices = true;
          max_handle_seconds = 0;
          sync_direct_chat_list = false;

          periodic_sync = true;

          private_chat_portal_meta = "always";

          provisioning = {
            prefix = "/_matrix/provision";
            shared_secret = "generate";
          };
        };

        logging = {
          min_level = "info";
          writers = [{
            type = "stdout";
            format = "pretty-colored";
          }];
        };
      };
    in
    {
      # Declare the agenix secret only when neither explicit password option is set
      age.secrets.bluebubbles-password = mkIf (cfg.blueBubblesPasswordFile == null && cfg.blueBubblesPassword == null) {
        file = ../../../secrets/bluebubbles-password.age;
        owner = "mautrix-imessage";
        group = "mautrix-imessage";
        mode = "0400";
      };

      nixpkgs.config.permittedInsecurePackages = [
        "olm-3.2.16"
      ];

      assertions = [
        {
          assertion = config.modules.services.communication.matrix-synapse.enable;
          message = "mautrix-imessage requires Matrix Synapse to be enabled";
        }
        {
          assertion = cfg.blueBubblesUrl != "";
          message = "mautrix-imessage requires blueBubblesUrl to be set";
        }
        {
          assertion = !(cfg.blueBubblesPasswordFile != null && cfg.blueBubblesPassword != null);
          message = "mautrix-imessage: cannot set both blueBubblesPasswordFile and blueBubblesPassword";
        }
      ];

      users.users.mautrix-imessage = {
        isSystemUser = true;
        group = "mautrix-imessage";
        home = dataDir;
        createHome = false;
      };

      users.groups.mautrix-imessage = {};

      systemd.tmpfiles.rules = [
        "d ${dataDir} 0755 mautrix-imessage mautrix-imessage -"
      ];

      systemd.services.mautrix-imessage = {
        description = "Mautrix-iMessage, a Matrix-iMessage puppeting bridge using BlueBubbles";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        before = [ "matrix-synapse.service" ];

        preStart = ''
          cp ${configFile} ${dataDir}/config.yaml
          chmod 640 ${dataDir}/config.yaml

          ${if passwordFile != null then ''
            BLUEBUBBLES_PASSWORD=$(cat ${passwordFile})
          '' else ''
            BLUEBUBBLES_PASSWORD="${cfg.blueBubblesPassword}"
          ''}

          ${pkgs.gnused}/bin/sed -i "s|BLUEBUBBLES_PASSWORD_PLACEHOLDER|$BLUEBUBBLES_PASSWORD|g" ${dataDir}/config.yaml

          echo "Generating registration file..."
          rm -f ${registrationFile}
          ${mautrix-imessage}/bin/mautrix-imessage \
            -c ${dataDir}/config.yaml \
            -r ${registrationFile} \
            -g

          ${pkgs.yq}/bin/yq -y '.url = "http://localhost:${toString cfg.port}"' ${registrationFile} > ${registrationFile}.tmp
          mv ${registrationFile}.tmp ${registrationFile}

          AS_TOKEN=$(${pkgs.yq}/bin/yq -r '.as_token' ${registrationFile})
          HS_TOKEN=$(${pkgs.yq}/bin/yq -r '.hs_token' ${registrationFile})
          PROVISION_SECRET=$(${pkgs.yq}/bin/yq -r '.de.sorunome.msc2409.push_ephemeral // "generate"' ${registrationFile})

          ${pkgs.yq}/bin/yq -y ".appservice.as_token = \"$AS_TOKEN\" | .appservice.hs_token = \"$HS_TOKEN\" | .bridge.provisioning.shared_secret = \"$PROVISION_SECRET\"" \
            ${dataDir}/config.yaml > ${dataDir}/config.yaml.tmp
          mv ${dataDir}/config.yaml.tmp ${dataDir}/config.yaml

          chown -R mautrix-imessage:mautrix-imessage ${dataDir}
          chmod 755 ${dataDir}
          chmod 644 ${registrationFile}
        '';

        serviceConfig = {
          Type = "simple";
          User = "mautrix-imessage";
          Group = "mautrix-imessage";
          WorkingDirectory = dataDir;
          ExecStart = "${mautrix-imessage}/bin/mautrix-imessage -c ${dataDir}/config.yaml";
          Restart = "on-failure";
          RestartSec = "10s";

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ dataDir ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          LockPersonality = true;
        };
      };

      modules.services.communication.matrix-synapse.appServiceConfigFiles = [ registrationFile ];
    }
  );
}
