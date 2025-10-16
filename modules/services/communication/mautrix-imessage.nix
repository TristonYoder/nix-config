{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.mautrix-imessage;
  matrixCfg = config.modules.services.communication.matrix-synapse;
  
  dataDir = "/var/lib/mautrix-imessage";
  registrationFile = "${dataDir}/registration.yaml";
  
  # Determine which password file to use
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
    
    # Use proxyVendor to ignore the out-of-sync vendor directory
    # and let Nix manage dependencies directly from go.mod
    proxyVendor = true;
    vendorHash = "sha256-JXQ7S6Z/lG3vBeaiVUIr2LPyCrhKCN5pEIRSeFy6Lzk=";
    
    buildInputs = [ pkgs.olm ];
    
    # The main package is in the root directory
    subPackages = [ "." ];
    
    # Set CGO flags for olm library
    env.CGO_ENABLED = 1;
    
    meta = with lib; {
      description = "A Matrix-iMessage puppeting bridge";
      homepage = "https://github.com/mautrix/imessage";
      license = licenses.agpl3Plus;
    };
  };
  
  # Generate bridge configuration (mautrix-imessage style, YAML format)
  settingsFormat = pkgs.formats.yaml {};
  configFile = settingsFormat.generate "config.yaml" {
    homeserver = {
      address = cfg.homeserverUrl;
      domain = cfg.domain;
      # Disable websocket to use HTTP appservice instead
      websocket_proxy = null;
      software = "standard";
      async_media = false;
    };
    
    appservice = {
      # HTTP listener settings (websocket_proxy is null, so we need a real port)
      hostname = "0.0.0.0";
      port = cfg.port;
      
      database = {
        # Use the correct database type with WAL mode
        type = "sqlite3-fk-wal";
        uri = "file:${dataDir}/mautrix-imessage.db?_txlock=immediate";
      };
      
      id = "imessage";
      bot = {
        username = "imessagebot";
        displayname = "iMessage Bridge Bot";
        avatar = "";  # Leave empty to use default icon instead of wrong maunium.net icon
      };
      
      ephemeral_events = true;
      
      # Tokens are loaded from the registration file
      as_token = "generate";
      hs_token = "generate";
    };
    
    # iMessage connector configuration
    imessage = {
      platform = "bluebubbles";
      bluebubbles_url = cfg.blueBubblesUrl;
      bluebubbles_password = "BLUEBUBBLES_PASSWORD_PLACEHOLDER";
    };
    
    bridge = {
      # Required: The Matrix user who will use the bridge
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
      
      # Periodically resync chat and contact info (updates display names)
      periodic_sync = true;
      
      # Provisioning API
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

  config = mkIf cfg.enable {
    # Declare the agenix secret (only when module is enabled to avoid user not found errors)
    # Only create if not using explicit password file or plaintext password
    age.secrets.bluebubbles-password = mkIf (cfg.blueBubblesPasswordFile == null && cfg.blueBubblesPassword == null) {
      file = ../../../secrets/bluebubbles-password.age;
      owner = "mautrix-imessage";
      group = "mautrix-imessage";
      mode = "0400";
    };
    
    # Allow deprecated olm library for Matrix bridge encryption
    # Note: olm is deprecated but still required by mautrix bridges for E2EE support
    nixpkgs.config.permittedInsecurePackages = [
      "olm-3.2.16"
    ];
    
    # Ensure Matrix Synapse is enabled
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

    # Create bridge user and group
    users.users.mautrix-imessage = {
      isSystemUser = true;
      group = "mautrix-imessage";
      home = dataDir;
      createHome = true;
    };
    
    users.groups.mautrix-imessage = {};

    # Create data directory (755 so matrix-synapse can read registration file)
    # Note: Use 'Z' to recursively set permissions even if directory already exists
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 mautrix-imessage mautrix-imessage -"
      "Z ${dataDir} 0755 mautrix-imessage mautrix-imessage -"
    ];

    # mautrix-imessage systemd service
    systemd.services.mautrix-imessage = {
      description = "Mautrix-iMessage, a Matrix-iMessage puppeting bridge using BlueBubbles";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      before = [ "matrix-synapse.service" ];  # Ensure registration file exists before Matrix starts
      requiredBy = [ "matrix-synapse.service" ];  # Matrix Synapse requires this service

      preStart = ''
        # Copy config file
        cp ${configFile} ${dataDir}/config.yaml
        chmod 640 ${dataDir}/config.yaml
        
        # Substitute BlueBubbles password from secret file
        ${if passwordFile != null then ''
          BLUEBUBBLES_PASSWORD=$(cat ${passwordFile})
        '' else ''
          BLUEBUBBLES_PASSWORD="${cfg.blueBubblesPassword}"
        ''}
        
        # Replace password placeholder in config
        ${pkgs.gnused}/bin/sed -i "s|BLUEBUBBLES_PASSWORD_PLACEHOLDER|$BLUEBUBBLES_PASSWORD|g" ${dataDir}/config.yaml
        
        # Always regenerate registration to ensure it has the correct URL
        echo "Generating registration file..."
        rm -f ${registrationFile}
        ${mautrix-imessage}/bin/mautrix-imessage \
          -c ${dataDir}/config.yaml \
          -r ${registrationFile} \
          -g
        
        # Fix the URL in the registration file (it generates as empty string)
        ${pkgs.yq}/bin/yq -y '.url = "http://localhost:${toString cfg.port}"' ${registrationFile} > ${registrationFile}.tmp
        mv ${registrationFile}.tmp ${registrationFile}
        
        # Extract tokens from registration file and update config
        AS_TOKEN=$(${pkgs.yq}/bin/yq -r '.as_token' ${registrationFile})
        HS_TOKEN=$(${pkgs.yq}/bin/yq -r '.hs_token' ${registrationFile})
        PROVISION_SECRET=$(${pkgs.yq}/bin/yq -r '.de.sorunome.msc2409.push_ephemeral // "generate"' ${registrationFile})
        
        # Update config with real tokens
        ${pkgs.yq}/bin/yq -y ".appservice.as_token = \"$AS_TOKEN\" | .appservice.hs_token = \"$HS_TOKEN\" | .bridge.provisioning.shared_secret = \"$PROVISION_SECRET\"" \
          ${dataDir}/config.yaml > ${dataDir}/config.yaml.tmp
        mv ${dataDir}/config.yaml.tmp ${dataDir}/config.yaml
        
        # Fix ownership first
        chown -R mautrix-imessage:mautrix-imessage ${dataDir}
        
        # Make directory world-readable and executable so matrix-synapse can traverse to the file
        chmod 755 ${dataDir}
        
        # Make registration file readable by matrix-synapse
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
        
        # Security hardening
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

    # Automatically add registration file to Matrix Synapse
    modules.services.communication.matrix-synapse.appServiceConfigFiles = [ registrationFile ];
  };
}

