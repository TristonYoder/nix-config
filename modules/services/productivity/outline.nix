{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.outline;
in
{
  options.modules.services.productivity.outline = {
    enable = mkEnableOption "Outline wiki and knowledge management system";

    domain = mkOption {
      type = types.str;
      default = "outline.${config.networking.domain}";
      description = "Domain for Outline";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Internal port for Outline service";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.outline or null;
      description = "Outline package to use";
    };

    # Core Configuration
    publicUrl = mkOption {
      type = types.str;
      default = "https://${cfg.domain}";
      description = "Public URL where Outline is accessible";
    };

    secretKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing secret key for sessions (32+ chars)";
    };

    utilsSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing utils secret for end-to-end encryption";
    };

    # Database
    databaseUrl = mkOption {
      type = types.str;
      default = "postgres://user:pass@localhost:5432/outline";
      description = "PostgreSQL database connection URL";
    };

    # Redis
    redisUrl = mkOption {
      type = types.str;
      default = "redis://localhost:6379";
      description = "Redis connection URL";
    };

    # SMTP Configuration
    smtp = mkOption {
      type = types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            default = "localhost";
            description = "SMTP server hostname";
          };
          port = mkOption {
            type = types.port;
            default = 587;
            description = "SMTP server port";
          };
          secure = mkOption {
            type = types.bool;
            default = false;
            description = "Use TLS/SSL for SMTP";
          };
          username = mkOption {
            type = types.str;
            default = "";
            description = "SMTP username";
          };
          passwordFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing SMTP password";
          };
          fromEmail = mkOption {
            type = types.str;
            default = "noreply@${config.networking.domain}";
            description = "From email address";
          };
          replyEmail = mkOption {
            type = types.str;
            default = "support@${config.networking.domain}";
            description = "Reply-to email address";
          };
          tlsCiphers = mkOption {
            type = types.str;
            default = "";
            description = "Custom TLS ciphers";
          };
        };
      };
      default = { };
      description = "SMTP email configuration";
    };

    # File Storage
    storage = mkOption {
      type = types.submodule {
        options = {
          storageType = mkOption {
            type = types.enum [ "local" "s3" ];
            default = "local";
            description = "Storage backend: 'local' or 's3'";
          };
          localRootDir = mkOption {
            type = types.str;
            default = "/data/docker-appdata/${cfg.domain}/data";
            description = "Local storage directory (for storageType=local)";
          };
          uploadMaxSize = mkOption {
            type = types.int;
            default = 26214400; # 25MB in bytes
            description = "Maximum file upload size in bytes";
          };
          # S3 options
          accessKey = mkOption {
            type = types.str;
            default = "";
            description = "S3 access key";
          };
          secretKeyFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing S3 secret key";
          };
          uploadBucketName = mkOption {
            type = types.str;
            default = "";
            description = "S3 bucket name";
          };
          uploadBucketUrl = mkOption {
            type = types.str;
            default = "";
            description = "S3 bucket URL";
          };
          region = mkOption {
            type = types.str;
            default = "";
            description = "S3 region";
          };
          forcePathStyle = mkOption {
            type = types.bool;
            default = false;
            description = "Force path-style S3 URLs";
          };
          acl = mkOption {
            type = types.str;
            default = "private";
            description = "S3 object ACL";
          };
          accelerateUrl = mkOption {
            type = types.str;
            default = "";
            description = "CloudFront accelerated URL";
          };
        };
      };
      default = { };
      description = "File storage configuration";
    };

    # User & Group
    user = mkOption {
      type = types.str;
      default = "outline";
      description = "User to run Outline as";
    };

    group = mkOption {
      type = types.str;
      default = "outline";
      description = "Group for Outline";
    };

    # Authentication Methods
    slackAuthentication = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Slack authentication";
          clientId = mkOption {
            type = types.str;
            default = "";
            description = "Slack app client ID";
          };
          secretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing Slack app secret";
          };
        };
      };
      default = { };
      description = "Slack OAuth authentication configuration";
    };

    slackIntegration = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Slack workspace integration";
          appId = mkOption {
            type = types.str;
            default = "";
            description = "Slack app ID";
          };
          messageActions = mkOption {
            type = types.bool;
            default = true;
            description = "Enable Slack message actions";
          };
          verificationTokenFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing Slack verification token";
          };
        };
      };
      default = { };
      description = "Slack workspace integration configuration";
    };

    googleAuthentication = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Google OAuth authentication";
          clientId = mkOption {
            type = types.str;
            default = "";
            description = "Google OAuth client ID";
          };
          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing Google OAuth client secret";
          };
        };
      };
      default = { };
      description = "Google OAuth authentication configuration";
    };

    microsoftAuthentication = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Microsoft/Azure AD authentication";
          clientId = mkOption {
            type = types.str;
            default = "";
            description = "Azure AD application client ID";
          };
          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing Azure AD client secret";
          };
          resourceAppId = mkOption {
            type = types.str;
            default = "";
            description = "Azure AD resource app ID";
          };
        };
      };
      default = { };
      description = "Microsoft Azure AD authentication configuration";
    };

    discordAuthentication = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Discord authentication";
          clientId = mkOption {
            type = types.str;
            default = "";
            description = "Discord app client ID";
          };
          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing Discord app secret";
          };
          serverId = mkOption {
            type = types.str;
            default = "";
            description = "Discord server ID for OAuth (optional)";
          };
          serverRoles = mkOption {
            type = types.str;
            default = "";
            description = "Required Discord server roles (comma-separated)";
          };
        };
      };
      default = { };
      description = "Discord authentication configuration";
    };

    oidcAuthentication = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "OIDC authentication";
          displayName = mkOption {
            type = types.str;
            default = "";
            description = "Display name for OIDC provider";
          };
          clientId = mkOption {
            type = types.str;
            default = "";
            description = "OIDC client ID";
          };
          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing OIDC client secret";
          };
          authUrl = mkOption {
            type = types.str;
            default = "";
            description = "OIDC authorization endpoint";
          };
          tokenUrl = mkOption {
            type = types.str;
            default = "";
            description = "OIDC token endpoint";
          };
          userinfoUrl = mkOption {
            type = types.str;
            default = "";
            description = "OIDC userinfo endpoint";
          };
          scopes = mkOption {
            type = types.str;
            default = "openid profile email";
            description = "OIDC scopes to request";
          };
          usernameClaim = mkOption {
            type = types.str;
            default = "preferred_username";
            description = "JWT claim to use for username";
          };
        };
      };
      default = { };
      description = "OIDC/OpenID Connect authentication configuration";
    };

    # Server Configuration
    concurrency = mkOption {
      type = types.int;
      default = 1;
      description = "Number of worker processes";
    };

    forceHttps = mkOption {
      type = types.bool;
      default = true;
      description = "Force HTTPS by redirecting HTTP to HTTPS";
    };

    defaultLanguage = mkOption {
      type = types.str;
      default = "en_US";
      description = "Default language locale";
    };

    # SSL/TLS Certificates
    sslCertFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to SSL certificate file";
    };

    sslKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to SSL key file";
    };

    # Branding
    logo = mkOption {
      type = types.str;
      default = "";
      description = "URL to custom logo";
    };

    cdnUrl = mkOption {
      type = types.str;
      default = "";
      description = "CDN URL for static assets";
    };

    # Rate Limiting
    rateLimiter = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "rate limiter";
          requests = mkOption {
            type = types.int;
            default = 1000;
            description = "Number of requests allowed in time window";
          };
          durationWindow = mkOption {
            type = types.int;
            default = 60;
            description = "Time window in seconds";
          };
        };
      };
      default = { };
      description = "Rate limiting configuration";
    };

    # Analytics & Monitoring
    googleAnalyticsId = mkOption {
      type = types.str;
      default = "";
      description = "Google Analytics tracking ID";
    };

    sentryDsn = mkOption {
      type = types.str;
      default = "";
      description = "Sentry DSN for error tracking";
    };

    sentryTunnel = mkOption {
      type = types.str;
      default = "";
      description = "Sentry tunnel URL";
    };

    debugOutput = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug output";
    };

    # Features
    enableUpdateCheck = mkOption {
      type = types.bool;
      default = true;
      description = "Enable checking for Outline updates";
    };

    maximumImportSize = mkOption {
      type = types.int;
      default = 5242880; # 5MB in bytes
      description = "Maximum import file size in bytes";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = mkIf (cfg.user != "root") {
      isSystemUser = true;
      group = cfg.group;
      home = "/var/lib/outline";
      createHome = true;
    };

    users.groups.${cfg.group} = mkIf (cfg.group != "root") { };

    # Generate environment file for Outline
    environment.etc."outline/outline.env" = {
      text = ''
        # Core
        NODE_ENV=production
        SECRET_KEY=${if cfg.secretKeyFile != null then builtins.readFile cfg.secretKeyFile else "CHANGE_ME_SECRET_KEY"}
        UTILS_SECRET=${if cfg.utilsSecretFile != null then builtins.readFile cfg.utilsSecretFile else "CHANGE_ME_UTILS_SECRET"}
        
        # URLs
        URL=${cfg.publicUrl}
        PORT=${toString cfg.port}
        
        # Database
        DATABASE_URL=${cfg.databaseUrl}
        
        # Redis
        REDIS_URL=${cfg.redisUrl}
        
        # SMTP
        SMTP_HOST=${cfg.smtp.host}
        SMTP_PORT=${toString cfg.smtp.port}
        SMTP_SECURE=${if cfg.smtp.secure then "true" else "false"}
        SMTP_USERNAME=${cfg.smtp.username}
        ${optionalString (cfg.smtp.passwordFile != null) "SMTP_PASSWORD=$(cat ${cfg.smtp.passwordFile})"}
        SMTP_FROM_EMAIL=${cfg.smtp.fromEmail}
        SMTP_REPLY_EMAIL=${cfg.smtp.replyEmail}
        ${optionalString (cfg.smtp.tlsCiphers != "") "SMTP_TLS_CIPHERS=${cfg.smtp.tlsCiphers}"}
        
        # Storage
        FILE_STORAGE_UPLOAD_MAX_SIZE=${toString cfg.storage.uploadMaxSize}
        STORAGE=${cfg.storage.storageType}
        ${optionalString (cfg.storage.storageType == "local") "FILE_STORAGE_LOCAL_ROOT_DIR=${cfg.storage.localRootDir}"}
        ${optionalString (cfg.storage.storageType == "s3") ''
          AWS_ACCESS_KEY_ID=${cfg.storage.accessKey}
          ${optionalString (cfg.storage.secretKeyFile != null) "AWS_SECRET_ACCESS_KEY=$(cat ${cfg.storage.secretKeyFile})"}
          AWS_REGION=${cfg.storage.region}
          AWS_S3_ACCELERATE_URL=${cfg.storage.accelerateUrl}
          AWS_S3_UPLOAD_BUCKET_NAME=${cfg.storage.uploadBucketName}
          AWS_S3_UPLOAD_BUCKET_URL=${cfg.storage.uploadBucketUrl}
          AWS_S3_FORCE_PATH_STYLE=${if cfg.storage.forcePathStyle then "true" else "false"}
          AWS_S3_ACL=${cfg.storage.acl}
        ''}
        
        # Slack Authentication
        ${optionalString cfg.slackAuthentication.enable ''
          SLACK_CLIENT_ID=${cfg.slackAuthentication.clientId}
          ${optionalString (cfg.slackAuthentication.secretFile != null) "SLACK_CLIENT_SECRET=$(cat ${cfg.slackAuthentication.secretFile})"}
        ''}
        
        # Slack Integration
        ${optionalString cfg.slackIntegration.enable ''
          SLACK_APP_ID=${cfg.slackIntegration.appId}
          SLACK_MESSAGE_ACTIONS=${if cfg.slackIntegration.messageActions then "true" else "false"}
          ${optionalString (cfg.slackIntegration.verificationTokenFile != null) "SLACK_VERIFICATION_TOKEN=$(cat ${cfg.slackIntegration.verificationTokenFile})"}
        ''}
        
        # Google Authentication
        ${optionalString cfg.googleAuthentication.enable ''
          GOOGLE_CLIENT_ID=${cfg.googleAuthentication.clientId}
          ${optionalString (cfg.googleAuthentication.clientSecretFile != null) "GOOGLE_CLIENT_SECRET=$(cat ${cfg.googleAuthentication.clientSecretFile})"}
        ''}
        
        # Microsoft/Azure Authentication
        ${optionalString cfg.microsoftAuthentication.enable ''
          AZURE_CLIENT_ID=${cfg.microsoftAuthentication.clientId}
          ${optionalString (cfg.microsoftAuthentication.clientSecretFile != null) "AZURE_CLIENT_SECRET=$(cat ${cfg.microsoftAuthentication.clientSecretFile})"}
          ${optionalString (cfg.microsoftAuthentication.resourceAppId != "") "AZURE_RESOURCE_APP_ID=${cfg.microsoftAuthentication.resourceAppId}"}
        ''}
        
        # Discord Authentication
        ${optionalString cfg.discordAuthentication.enable ''
          DISCORD_CLIENT_ID=${cfg.discordAuthentication.clientId}
          ${optionalString (cfg.discordAuthentication.clientSecretFile != null) "DISCORD_CLIENT_SECRET=$(cat ${cfg.discordAuthentication.clientSecretFile})"}
          ${optionalString (cfg.discordAuthentication.serverId != "") "DISCORD_SERVER_ID=${cfg.discordAuthentication.serverId}"}
          ${optionalString (cfg.discordAuthentication.serverRoles != "") "DISCORD_SERVER_ROLES=${cfg.discordAuthentication.serverRoles}"}
        ''}
        
        # OIDC Authentication
        ${optionalString cfg.oidcAuthentication.enable ''
          OIDC_DISPLAY_NAME=${cfg.oidcAuthentication.displayName}
          OIDC_CLIENT_ID=${cfg.oidcAuthentication.clientId}
          ${optionalString (cfg.oidcAuthentication.clientSecretFile != null) "OIDC_CLIENT_SECRET=$(cat ${cfg.oidcAuthentication.clientSecretFile})"}
          OIDC_AUTH_URI=${cfg.oidcAuthentication.authUrl}
          OIDC_TOKEN_URI=${cfg.oidcAuthentication.tokenUrl}
          OIDC_USERINFO_URI=${cfg.oidcAuthentication.userinfoUrl}
          OIDC_SCOPES=${cfg.oidcAuthentication.scopes}
          OIDC_USERNAME_CLAIM=${cfg.oidcAuthentication.usernameClaim}
        ''}
        
        # Server Config
        WEB_CONCURRENCY=${toString cfg.concurrency}
        FORCE_HTTPS=${if cfg.forceHttps then "true" else "false"}
        DEFAULT_LANGUAGE=${cfg.defaultLanguage}
        
        # SSL
        ${optionalString (cfg.sslCertFile != null) "SSL_CERT_FILE=${cfg.sslCertFile}"}
        ${optionalString (cfg.sslKeyFile != null) "SSL_KEY_FILE=${cfg.sslKeyFile}"}
        
        # Branding
        ${optionalString (cfg.logo != "") "LOGO_URL=${cfg.logo}"}
        ${optionalString (cfg.cdnUrl != "") "CDN_URL=${cfg.cdnUrl}"}
        
        # Rate Limiting
        ${optionalString cfg.rateLimiter.enable ''
          RATE_LIMITER_ENABLED=true
          RATE_LIMITER_REQUESTS=${toString cfg.rateLimiter.requests}
          RATE_LIMITER_DURATION_WINDOW=${toString cfg.rateLimiter.durationWindow}
        ''}
        
        # Analytics
        ${optionalString (cfg.googleAnalyticsId != "") "GOOGLE_ANALYTICS_ID=${cfg.googleAnalyticsId}"}
        ${optionalString (cfg.sentryDsn != "") "SENTRY_DSN=${cfg.sentryDsn}"}
        ${optionalString (cfg.sentryTunnel != "") "SENTRY_TUNNEL=${cfg.sentryTunnel}"}
        
        # Debug
        DEBUG=${if cfg.debugOutput then "true" else "false"}
        
        # Features
        UPDATE_CHECK_ENABLED=${if cfg.enableUpdateCheck then "true" else "false"}
        MAXIMUM_IMPORT_SIZE=${toString cfg.maximumImportSize}
      '';
      mode = "0600";
      user = cfg.user;
      group = cfg.group;
    };

    # Caddy virtual host for reverse proxy
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Outline";
      category = "productivity";
      icon = "outline";
    };
  };
}
