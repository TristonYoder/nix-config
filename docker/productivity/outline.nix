# Auto-generated using compose2nix v0.3.2.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."outline-outline" = {
    image = "docker.getoutline.com/outlinewiki/outline:latest";
    environment = {
      "AWS_ACCESS_KEY_ID" = "get_a_key_from_aws";
      "AWS_REGION" = "xx-xxxx-x";
      "AWS_S3_ACCELERATE_URL" = "";
      "AWS_S3_ACL" = "private";
      "AWS_S3_FORCE_PATH_STYLE" = "true";
      "AWS_S3_UPLOAD_BUCKET_NAME" = "bucket_name_here";
      "AWS_S3_UPLOAD_BUCKET_URL" = "http://s3:4569";
      "AWS_SECRET_ACCESS_KEY" = "get_the_secret_of_above_key";
      "AZURE_CLIENT_ID" = "";
      "AZURE_CLIENT_SECRET" = "";
      "AZURE_RESOURCE_APP_ID" = "";
      "CDN_URL" = "";
      "COLLABORATION_URL" = "";
      "DATABASE_CONNECTION_POOL_MAX" = "";
      "DATABASE_CONNECTION_POOL_MIN" = "";
      "DATABASE_URL" = "postgres://user:pass@postgres:5432/outline";
      "DEBUG" = "http";
      "DEFAULT_LANGUAGE" = "en_US";
      "DISCORD_CLIENT_ID" = "";
      "DISCORD_CLIENT_SECRET" = "";
      "DISCORD_SERVER_ID" = "";
      "DISCORD_SERVER_ROLES" = "";
      "DROPBOX_APP_KEY" = "";
      "ENABLE_UPDATES" = "true";
      "FILE_STORAGE" = "local";
      "FILE_STORAGE_IMPORT_MAX_SIZE" = "";
      "FILE_STORAGE_LOCAL_ROOT_DIR" = "/var/lib/outline/data";
      "FILE_STORAGE_UPLOAD_MAX_SIZE" = "262144000";
      "FILE_STORAGE_WORKSPACE_IMPORT_MAX_SIZE" = "";
      "FORCE_HTTPS" = "false";
      "GITHUB_APP_ID" = "";
      "GITHUB_APP_NAME" = "";
      "GITHUB_APP_PRIVATE_KEY" = "";
      "GITHUB_CLIENT_ID" = "";
      "GITHUB_CLIENT_SECRET" = "";
      "GITHUB_WEBHOOK_SECRET" = "";
      "GOOGLE_CLIENT_ID" = "723733122143-vsmk4qbabsrkqsh46ocg8nt6u80l9d2c.apps.googleusercontent.com";
      "GOOGLE_CLIENT_SECRET" = "{a_secret_was_here}";
      "IFRAMELY_API_KEY" = "";
      "IFRAMELY_URL" = "";
      "LINEAR_CLIENT_ID" = "";
      "LINEAR_CLIENT_SECRET" = "";
      "LOG_LEVEL" = "info";
      "NODE_ENV" = "production";
      "OIDC_AUTH_URI" = "";
      "OIDC_CLIENT_ID" = "";
      "OIDC_CLIENT_SECRET" = "";
      "OIDC_DISPLAY_NAME" = "OpenID Connect";
      "OIDC_LOGOUT_URI" = "";
      "OIDC_SCOPES" = "openid profile email";
      "OIDC_TOKEN_URI" = "";
      "OIDC_USERINFO_URI" = "";
      "OIDC_USERNAME_CLAIM" = "preferred_username";
      "PGSSLMODE" = "disable";
      "PORT" = "3000";
      "RATE_LIMITER_DURATION_WINDOW" = "60";
      "RATE_LIMITER_ENABLED" = "true";
      "RATE_LIMITER_REQUESTS" = "1000";
      "REDIS_URL" = "redis://redis:6379";
      "SECRET_KEY" = "{a_secret_was_here}";
      "SENTRY_DSN" = "";
      "SENTRY_TUNNEL" = "";
      "SLACK_APP_ID" = "";
      "SLACK_CLIENT_ID" = "";
      "SLACK_CLIENT_SECRET" = "";
      "SLACK_MESSAGE_ACTIONS" = "true";
      "SLACK_VERIFICATION_TOKEN" = "";
      "SMTP_FROM_EMAIL" = "";
      "SMTP_PASSWORD" = "";
      "SMTP_SERVICE" = "";
      "SMTP_USERNAME" = "";
      "SSL_CERT" = "";
      "SSL_KEY" = "";
      "URL" = "https://outline.tpdemo.theyoder.family/";
      "UTILS_SECRET" = "{a_secret_was_here}";
      "WEB_CONCURRENCY" = "1";
    };
    volumes = [
      "outline_storage-data:/var/lib/outline/data:rw"
    ];
    ports = [
      "6591:3000/tcp"
    ];
    dependsOn = [
      "outline-postgres"
      "outline-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=outline"
      "--network=outline_default"
    ];
  };
  systemd.services."docker-outline-outline" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-outline_default.service"
      "docker-volume-outline_storage-data.service"
    ];
    requires = [
      "docker-network-outline_default.service"
      "docker-volume-outline_storage-data.service"
    ];
    partOf = [
      "docker-compose-outline-root.target"
    ];
    wantedBy = [
      "docker-compose-outline-root.target"
    ];
  };
  virtualisation.oci-containers.containers."outline-postgres" = {
    image = "postgres";
    environment = {
      "AWS_ACCESS_KEY_ID" = "get_a_key_from_aws";
      "AWS_REGION" = "xx-xxxx-x";
      "AWS_S3_ACCELERATE_URL" = "";
      "AWS_S3_ACL" = "private";
      "AWS_S3_FORCE_PATH_STYLE" = "true";
      "AWS_S3_UPLOAD_BUCKET_NAME" = "bucket_name_here";
      "AWS_S3_UPLOAD_BUCKET_URL" = "http://s3:4569";
      "AWS_SECRET_ACCESS_KEY" = "get_the_secret_of_above_key";
      "AZURE_CLIENT_ID" = "";
      "AZURE_CLIENT_SECRET" = "";
      "AZURE_RESOURCE_APP_ID" = "";
      "CDN_URL" = "";
      "COLLABORATION_URL" = "";
      "DATABASE_CONNECTION_POOL_MAX" = "";
      "DATABASE_CONNECTION_POOL_MIN" = "";
      "DATABASE_URL" = "postgres://user:pass@postgres:5432/outline";
      "DEBUG" = "http";
      "DEFAULT_LANGUAGE" = "en_US";
      "DISCORD_CLIENT_ID" = "";
      "DISCORD_CLIENT_SECRET" = "";
      "DISCORD_SERVER_ID" = "";
      "DISCORD_SERVER_ROLES" = "";
      "DROPBOX_APP_KEY" = "";
      "ENABLE_UPDATES" = "true";
      "FILE_STORAGE" = "local";
      "FILE_STORAGE_IMPORT_MAX_SIZE" = "";
      "FILE_STORAGE_LOCAL_ROOT_DIR" = "/var/lib/outline/data";
      "FILE_STORAGE_UPLOAD_MAX_SIZE" = "262144000";
      "FILE_STORAGE_WORKSPACE_IMPORT_MAX_SIZE" = "";
      "FORCE_HTTPS" = "false";
      "GITHUB_APP_ID" = "";
      "GITHUB_APP_NAME" = "";
      "GITHUB_APP_PRIVATE_KEY" = "";
      "GITHUB_CLIENT_ID" = "";
      "GITHUB_CLIENT_SECRET" = "";
      "GITHUB_WEBHOOK_SECRET" = "";
      "GOOGLE_CLIENT_ID" = "723733122143-vsmk4qbabsrkqsh46ocg8nt6u80l9d2c.apps.googleusercontent.com";
      "GOOGLE_CLIENT_SECRET" = "{a_secret_was_here}";
      "IFRAMELY_API_KEY" = "";
      "IFRAMELY_URL" = "";
      "LINEAR_CLIENT_ID" = "";
      "LINEAR_CLIENT_SECRET" = "";
      "LOG_LEVEL" = "info";
      "NODE_ENV" = "production";
      "OIDC_AUTH_URI" = "";
      "OIDC_CLIENT_ID" = "";
      "OIDC_CLIENT_SECRET" = "";
      "OIDC_DISPLAY_NAME" = "OpenID Connect";
      "OIDC_LOGOUT_URI" = "";
      "OIDC_SCOPES" = "openid profile email";
      "OIDC_TOKEN_URI" = "";
      "OIDC_USERINFO_URI" = "";
      "OIDC_USERNAME_CLAIM" = "preferred_username";
      "PGSSLMODE" = "disable";
      "PORT" = "3000";
      "POSTGRES_DB" = "outline";
      "POSTGRES_PASSWORD" = "pass";
      "POSTGRES_USER" = "user";
      "RATE_LIMITER_DURATION_WINDOW" = "60";
      "RATE_LIMITER_ENABLED" = "true";
      "RATE_LIMITER_REQUESTS" = "1000";
      "REDIS_URL" = "redis://redis:6379";
      "SECRET_KEY" = "{a_secret_was_here}";
      "SENTRY_DSN" = "";
      "SENTRY_TUNNEL" = "";
      "SLACK_APP_ID" = "";
      "SLACK_CLIENT_ID" = "";
      "SLACK_CLIENT_SECRET" = "";
      "SLACK_MESSAGE_ACTIONS" = "true";
      "SLACK_VERIFICATION_TOKEN" = "";
      "SMTP_FROM_EMAIL" = "";
      "SMTP_PASSWORD" = "";
      "SMTP_SERVICE" = "";
      "SMTP_USERNAME" = "";
      "SSL_CERT" = "";
      "SSL_KEY" = "";
      "URL" = "https://outline.tpdemo.theyoder.family/";
      "UTILS_SECRET" = "{a_secret_was_here}";
      "WEB_CONCURRENCY" = "1";
    };
    volumes = [
      "outline_database-data:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"pg_isready\", \"-d\", \"outline\", \"-U\", \"user\"]"
      "--health-interval=30s"
      "--health-retries=3"
      "--health-timeout=20s"
      "--network-alias=postgres"
      "--network=outline_default"
    ];
  };
  systemd.services."docker-outline-postgres" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-outline_default.service"
      "docker-volume-outline_database-data.service"
    ];
    requires = [
      "docker-network-outline_default.service"
      "docker-volume-outline_database-data.service"
    ];
    partOf = [
      "docker-compose-outline-root.target"
    ];
    wantedBy = [
      "docker-compose-outline-root.target"
    ];
  };
  virtualisation.oci-containers.containers."outline-redis" = {
    image = "redis";
    environment = {
      "AWS_ACCESS_KEY_ID" = "get_a_key_from_aws";
      "AWS_REGION" = "xx-xxxx-x";
      "AWS_S3_ACCELERATE_URL" = "";
      "AWS_S3_ACL" = "private";
      "AWS_S3_FORCE_PATH_STYLE" = "true";
      "AWS_S3_UPLOAD_BUCKET_NAME" = "bucket_name_here";
      "AWS_S3_UPLOAD_BUCKET_URL" = "http://s3:4569";
      "AWS_SECRET_ACCESS_KEY" = "get_the_secret_of_above_key";
      "AZURE_CLIENT_ID" = "";
      "AZURE_CLIENT_SECRET" = "";
      "AZURE_RESOURCE_APP_ID" = "";
      "CDN_URL" = "";
      "COLLABORATION_URL" = "";
      "DATABASE_CONNECTION_POOL_MAX" = "";
      "DATABASE_CONNECTION_POOL_MIN" = "";
      "DATABASE_URL" = "postgres://user:pass@postgres:5432/outline";
      "DEBUG" = "http";
      "DEFAULT_LANGUAGE" = "en_US";
      "DISCORD_CLIENT_ID" = "";
      "DISCORD_CLIENT_SECRET" = "";
      "DISCORD_SERVER_ID" = "";
      "DISCORD_SERVER_ROLES" = "";
      "DROPBOX_APP_KEY" = "";
      "ENABLE_UPDATES" = "true";
      "FILE_STORAGE" = "local";
      "FILE_STORAGE_IMPORT_MAX_SIZE" = "";
      "FILE_STORAGE_LOCAL_ROOT_DIR" = "/var/lib/outline/data";
      "FILE_STORAGE_UPLOAD_MAX_SIZE" = "262144000";
      "FILE_STORAGE_WORKSPACE_IMPORT_MAX_SIZE" = "";
      "FORCE_HTTPS" = "false";
      "GITHUB_APP_ID" = "";
      "GITHUB_APP_NAME" = "";
      "GITHUB_APP_PRIVATE_KEY" = "";
      "GITHUB_CLIENT_ID" = "";
      "GITHUB_CLIENT_SECRET" = "";
      "GITHUB_WEBHOOK_SECRET" = "";
      "GOOGLE_CLIENT_ID" = "723733122143-vsmk4qbabsrkqsh46ocg8nt6u80l9d2c.apps.googleusercontent.com";
      "GOOGLE_CLIENT_SECRET" = "{a_secret_was_here}";
      "IFRAMELY_API_KEY" = "";
      "IFRAMELY_URL" = "";
      "LINEAR_CLIENT_ID" = "";
      "LINEAR_CLIENT_SECRET" = "";
      "LOG_LEVEL" = "info";
      "NODE_ENV" = "production";
      "OIDC_AUTH_URI" = "";
      "OIDC_CLIENT_ID" = "";
      "OIDC_CLIENT_SECRET" = "";
      "OIDC_DISPLAY_NAME" = "OpenID Connect";
      "OIDC_LOGOUT_URI" = "";
      "OIDC_SCOPES" = "openid profile email";
      "OIDC_TOKEN_URI" = "";
      "OIDC_USERINFO_URI" = "";
      "OIDC_USERNAME_CLAIM" = "preferred_username";
      "PGSSLMODE" = "disable";
      "PORT" = "3000";
      "RATE_LIMITER_DURATION_WINDOW" = "60";
      "RATE_LIMITER_ENABLED" = "true";
      "RATE_LIMITER_REQUESTS" = "1000";
      "REDIS_URL" = "redis://redis:6379";
      "SECRET_KEY" = "{a_secret_was_here}";
      "SENTRY_DSN" = "";
      "SENTRY_TUNNEL" = "";
      "SLACK_APP_ID" = "";
      "SLACK_CLIENT_ID" = "";
      "SLACK_CLIENT_SECRET" = "";
      "SLACK_MESSAGE_ACTIONS" = "true";
      "SLACK_VERIFICATION_TOKEN" = "";
      "SMTP_FROM_EMAIL" = "";
      "SMTP_PASSWORD" = "";
      "SMTP_SERVICE" = "";
      "SMTP_USERNAME" = "";
      "SSL_CERT" = "";
      "SSL_KEY" = "";
      "URL" = "https://outline.tpdemo.theyoder.family/";
      "UTILS_SECRET" = "{a_secret_was_here}";
      "WEB_CONCURRENCY" = "1";
    };
    volumes = [
      "/etc/nixos/docker/dockercompose/outline/redis.conf:/redis.conf:rw"
    ];
    cmd = [ "redis-server" "/redis.conf" ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"redis-cli\", \"ping\"]"
      "--health-interval=10s"
      "--health-retries=3"
      "--health-timeout=30s"
      "--network-alias=redis"
      "--network=outline_default"
    ];
  };
  systemd.services."docker-outline-redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-outline_default.service"
    ];
    requires = [
      "docker-network-outline_default.service"
    ];
    partOf = [
      "docker-compose-outline-root.target"
    ];
    wantedBy = [
      "docker-compose-outline-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-outline_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f outline_default";
    };
    script = ''
      docker network inspect outline_default || docker network create outline_default
    '';
    partOf = [ "docker-compose-outline-root.target" ];
    wantedBy = [ "docker-compose-outline-root.target" ];
  };

  # Volumes
  systemd.services."docker-volume-outline_database-data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect outline_database-data || docker volume create outline_database-data
    '';
    partOf = [ "docker-compose-outline-root.target" ];
    wantedBy = [ "docker-compose-outline-root.target" ];
  };
  systemd.services."docker-volume-outline_storage-data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect outline_storage-data || docker volume create outline_storage-data
    '';
    partOf = [ "docker-compose-outline-root.target" ];
    wantedBy = [ "docker-compose-outline-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-outline-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
