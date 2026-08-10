# photography.carolineelizabeth.com - WordPress photography portfolio site
# Professional photography portfolio with WordPress CMS and MySQL database
# Auto-generated using compose2nix v0.2.0-pre.
{ config, pkgs, lib, ... }:

let
  # PHP upload limits for the WordPress container. The official image ships
  # upload_max_filesize=2M / post_max_size=8M, which caps media uploads well
  # below what the site needs. Mounted into conf.d so it overrides the defaults.
  phpUploadsIni = pkgs.writeText "photography-carolineelizabeth-uploads.ini" ''
    file_uploads = On
    upload_max_filesize = 1G
    post_max_size = 1G
    memory_limit = 1G
    max_execution_time = 600
    max_input_time = 600
  '';
in
{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."photography_carolineelizabeth-db" = {
    # MySQL 5.7 went EOL in Oct 2023. Migrated to 8.0 via dump/restore rather
    # than an in-place upgrade: 8.0 rewrites the data dir irreversibly, so this
    # points at a NEW directory and leaves the 5.7 data untouched. Rollback is
    # reverting this file — see scripts/wordpress-mysql-upgrade.sh.
    image = "mysql:8.0";
    environmentFiles = [
      config.age.secrets.wordpress-photography-mysql.path
    ];
    environment = {
      MYSQL_DATABASE = "wordpress";
      # MYSQL_PASSWORD loaded from secret file
      # MYSQL_ROOT_PASSWORD loaded from secret file
      MYSQL_USER = "wordpress";
    };
    volumes = [
      "/data/docker-appdata/photography-carolineelizabeth/database-8.0:/var/lib/mysql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=photography-carolineelizabeth_default"
    ];
  };
  systemd.services."docker-photography_carolineelizabeth-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-photography-carolineelizabeth_default.service"
    ];
    requires = [
      "docker-network-photography-carolineelizabeth_default.service"
    ];
    partOf = [
      "docker-compose-photography_carolineelizabeth-root.target"
    ];
    wantedBy = [
      "docker-compose-photography_carolineelizabeth-root.target"
    ];
  };
  virtualisation.oci-containers.containers."photography_carolineelizabeth-wordpress" = {
    # Pinned to the php8.3 line rather than :latest. Watchtower updates every
    # container on this host unfiltered, so :latest would let it move the site
    # onto a new PHP major without warning — the usual way plugins/themes break.
    # WP core itself lives in the bind-mounted webroot and self-updates, so this
    # pins the runtime only, not the CMS version.
    image = "wordpress:php8.3-apache";
    environmentFiles = [
      config.age.secrets.wordpress-photography-wp.path
    ];
    environment = {
      WORDPRESS_DB_HOST = "db:3306";
      # WORDPRESS_DB_PASSWORD loaded from secret file
      WORDPRESS_DB_USER = "wordpress";
    };
    volumes = [
      "/data/docker-appdata/photography-carolineelizabeth/wp-backup/:/var/www/html:rw"
      "${phpUploadsIni}:/usr/local/etc/php/conf.d/uploads.ini:ro"
    ];
    ports = [
      "1996:80/tcp"
    ];
    dependsOn = [
      "photography_carolineelizabeth-db"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=wordpress"
      "--network=photography-carolineelizabeth_default"
    ];
  };
  systemd.services."docker-photography_carolineelizabeth-wordpress" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-photography-carolineelizabeth_default.service"
    ];
    requires = [
      "docker-network-photography-carolineelizabeth_default.service"
    ];
    partOf = [
      "docker-compose-photography_carolineelizabeth-root.target"
    ];
    wantedBy = [
      "docker-compose-photography_carolineelizabeth-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-photography-carolineelizabeth_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.docker}/bin/docker network rm -f photography-carolineelizabeth_default";
    };
    script = ''
      docker network inspect photography-carolineelizabeth_default || docker network create photography-carolineelizabeth_default
    '';
    partOf = [ "docker-compose-photography_carolineelizabeth-root.target" ];
    wantedBy = [ "docker-compose-photography_carolineelizabeth-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-photography_carolineelizabeth-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
