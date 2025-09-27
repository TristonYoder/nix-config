{ self, config, lib, pkgs, ... }: {
  services = {
    nextcloud = {
      enable = true;
      hostName = "nextcloud.theyoder.family";
      # Need to manually increment with every major upgrade.
      package = pkgs.nextcloud31;
      # Let NixOS install and configure the database automatically.
      database.createLocally = true;
      # Let NixOS install and configure Redis caching automatically.
      configureRedis = true;
      # Increase the maximum file upload size.
      maxUploadSize = "16G";
      https = false;
      autoUpdateApps.enable = true;
      settings = {
        overwriteProtocol = "https";
        default_phone_region = "US";
        trusted_domains = [
          "nextcloud.theyoder.family"
          "10.150.100.30" # Optional LAN IP
          ];
      };
      config = {
        dbname = "nextcloud";
        dbhost = "/run/postgresql";
        dbtype = "pgsql";
        adminuser = "TristonYoder";
        adminpassFile = "/etc/nixos/nextcloud/admin-pass";
      };
      # Suggested by Nextcloud's health check.
      phpOptions."opcache.interned_strings_buffer" = "16";
    };
    # Nightly database backups.
    postgresqlBackup = {
      enable = true;
      startAt = "*-*-* 01:15:00";
    };

    nginx.enable = false;

  };

  systemd.tmpfiles.rules = [
    "d /var/lib/nextcloud/config 0755 nextcloud nextcloud -"
    "f /var/lib/nextcloud/config/config.php 0640 nextcloud nextcloud -"
  ];

  users.users.caddy.extraGroups = [ "nextcloud" ];

services.phpfpm.pools.nextcloud = {
  user = "nextcloud";
  group = "nextcloud";
  settings = {
    "listen" = "/run/phpfpm/nextcloud.sock";
    "listen.owner" = "nextcloud";
    "listen.group" = "nextcloud";
    "listen.mode" = "0660";
  };
};


}
