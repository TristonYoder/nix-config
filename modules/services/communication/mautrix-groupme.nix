{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.mautrix-groupme;
  matrixCfg = config.modules.services.communication.matrix-synapse;
  
  dataDir = "/var/lib/mautrix-groupme";
  registrationFile = "${dataDir}/registration.yaml";
  
  # Build the Beeper GroupMe bridge from source
  mautrix-groupme = pkgs.buildGoModule rec {
    pname = "mautrix-groupme";
    version = "unstable-2024-01-01";
    
    src = pkgs.fetchFromGitHub {
      owner = "beeper";
      repo = "groupme";
      rev = "master";
      sha256 = "sha256-VQWW3FWW5Q+kN+ajun8OYRfk+6KbH5swJm6uwumLfu4=";
    };
    
    vendorHash = "sha256-bkhznT8nXGuwH9gInjTOh6jINiSVRfQbBsjVztvfHFE=";
    
    buildInputs = [ pkgs.olm ];
    
    # The main package is in the root directory
    subPackages = [ "." ];
    
    # Set CGO flags for olm library (using env as recommended)
    env.CGO_ENABLED = 1;
    
    meta = with lib; {
      description = "A Matrix-GroupMe puppeting bridge";
      homepage = "https://github.com/beeper/groupme";
      license = licenses.agpl3Only;
    };
  };
  
  # Generate bridge configuration (mautrix style, YAML format)
  settingsFormat = pkgs.formats.yaml {};
  configFile = settingsFormat.generate "config.yaml" {
    homeserver = {
      address = cfg.homeserverUrl;
      domain = cfg.domain;
    };
    
    appservice = {
      address = "http://localhost:${toString cfg.port}";
      hostname = "0.0.0.0";
      port = cfg.port;
      
      database = {
        type = "sqlite3";
        uri = "${dataDir}/mautrix-groupme.db";
      };
      
      id = "groupme";
      bot = {
        username = "groupmebot";
        displayname = "GroupMe Bridge Bot";
        avatar = "mxc://maunium.net/ygtkteZsXnGJLJHRchUwYWak";
      };
      
      # Explicitly set sender_localpart to match bot username
      sender_localpart = "groupmebot";
      ephemeral_events = false;
      
      # Tokens are loaded from the registration file
      as_token = "generate";
      hs_token = "generate";
    };
    
    bridge = {
      username_template = "groupme_{{.}}";
      displayname_template = "{{.DisplayName}} (GroupMe)";
      
      permissions = lib.listToAttrs (map (user: {
        name = user;
        value = "admin";
      }) cfg.provisioningWhitelist);
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
  options.modules.services.communication.mautrix-groupme = {
    enable = mkEnableOption "mautrix-groupme Matrix bridge";
    
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
      default = 29318;
      description = "Port for the bridge's appservice listener";
    };
    
    provisioningWhitelist = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "@admin:example.com" ];
      description = "List of Matrix user IDs allowed to use the bridge";
    };
  };

  config = mkIf cfg.enable {
    # Allow deprecated olm library for Matrix bridge encryption
    # Note: olm is deprecated but still required by mautrix bridges for E2EE support
    nixpkgs.config.permittedInsecurePackages = [
      "olm-3.2.16"
    ];
    
    # Ensure Matrix Synapse is enabled
    assertions = [
      {
        assertion = config.modules.services.communication.matrix-synapse.enable;
        message = "mautrix-groupme requires Matrix Synapse to be enabled";
      }
    ];

    # Create bridge user and group
    users.users.mautrix-groupme = {
      isSystemUser = true;
      group = "mautrix-groupme";
      home = dataDir;
      createHome = true;
    };
    
    users.groups.mautrix-groupme = {};

    # Create data directory (755 so matrix-synapse can read registration file)
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 mautrix-groupme mautrix-groupme -"
    ];

    # mautrix-groupme systemd service
    systemd.services.mautrix-groupme = {
      description = "Mautrix-GroupMe, a Matrix-GroupMe puppeting bridge";
      wantedBy = [ "multi-user.target" ];
      wants = [ "matrix-synapse.service" "network-online.target" ];
      after = [ "matrix-synapse.service" "network-online.target" ];

      preStart = ''
        # Copy config file
        cp ${configFile} ${dataDir}/config.yaml
        chmod 640 ${dataDir}/config.yaml
        
        # Always regenerate registration to ensure it matches config
        echo "Generating registration file..."
        rm -f ${registrationFile}
        ${mautrix-groupme}/bin/groupme \
          -c ${dataDir}/config.yaml \
          -r ${registrationFile} \
          -g
        
        # Fix sender_localpart in registration to match bot username
        ${pkgs.yq}/bin/yq -y '.sender_localpart = "groupmebot"' ${registrationFile} > ${registrationFile}.tmp
        mv ${registrationFile}.tmp ${registrationFile}
        
        # Extract tokens from registration file and update config
        AS_TOKEN=$(${pkgs.yq}/bin/yq -r '.as_token' ${registrationFile})
        HS_TOKEN=$(${pkgs.yq}/bin/yq -r '.hs_token' ${registrationFile})
        
        # Update config with real tokens
        ${pkgs.yq}/bin/yq -y ".appservice.as_token = \"$AS_TOKEN\" | .appservice.hs_token = \"$HS_TOKEN\"" \
          ${dataDir}/config.yaml > ${dataDir}/config.yaml.tmp
        mv ${dataDir}/config.yaml.tmp ${dataDir}/config.yaml
        
        # Make registration file readable by matrix-synapse
        chmod 644 ${registrationFile}
        
        # Make directory world-executable so matrix-synapse can traverse to the file
        chmod 755 ${dataDir}
        
        # Fix ownership
        chown -R mautrix-groupme:mautrix-groupme ${dataDir}
      '';

      serviceConfig = {
        Type = "simple";
        User = "mautrix-groupme";
        Group = "mautrix-groupme";
        WorkingDirectory = dataDir;
        ExecStart = "${mautrix-groupme}/bin/groupme -c ${dataDir}/config.yaml";
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

