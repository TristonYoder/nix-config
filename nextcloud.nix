{ self, config, lib, pkgs, ... }: 
{
  environment.etc."nextcloud-admin-pass".text = "-oJn8mUXeW@J-BW4tD4XcD-prjnbZB*MCsrnN7*mmgXjJGVbN7U";
  # services.nextcloud = {
  #   enable = true;
  #   package = pkgs.nextcloud30;
  #   hostName = "localhost";
  #   config.adminpassFile = "/etc/nextcloud-admin-pass";
  #   config.dbtype = "pgsql";
  # };
  #NextCloud Config
  # Based on https://carjorvaz.com/posts/the-holy-grail-nextcloud-setup-made-easy-by-nixos/
  
  # security.acme = {
  #   acceptTerms = true;
  #   defaults = {
  #     email = "wes+barn-acme@jupiterbroadcasting.com";
  #     dnsProvider = "cloudflare";
  #     # location of your CLOUDFLARE_DNS_API_TOKEN=[value]
  #     # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#EnvironmentFile=
  #     environmentFile = "/REPLACE/WITH/YOUR/PATH";
  #   };
  # };

  services = {
    # nginx.virtualHosts = {
    #   "YOUR.DOMAIN.NAME" = {
    #     forceSSL = true;
    #     enableACME = true;
    #     # Use DNS Challenege.
    #     acmeRoot = null;
    #   };
    # };
    
    nextcloud = {
      enable = true;
      hostName = "david";
      home = "/data/docker-appdata/nextcloud/";
      # Need to manually increment with every major upgrade.
      package = pkgs.nextcloud30;
      # Let NixOS install and configure the database automatically.
      database.createLocally = true;
      # Let NixOS install and configure Redis caching automatically.
      # configureRedis = true;
      # Increase the maximum file upload size.
      maxUploadSize = "32G";
      # https = true;
      # autoUpdateApps.enable = true;
      # extraAppsEnable = true;
      # extraApps = with config.services.nextcloud.package.packages.apps; {
      #   # List of apps we want to install and are already packaged in
      #   # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/nextcloud-apps.json
      #   inherit calendar contacts notes onlyoffice tasks cookbook qownnotesapi;
      #   # Custom app example.
      #   # socialsharing_telegram = pkgs.fetchNextcloudApp rec {
      #   #   url =
      #   #     "https://github.com/nextcloud-releases/socialsharing/releases/download/v3.0.1/socialsharing_telegram-v3.0.1.tar.gz";
      #   #   license = "agpl3";
      #   #   sha256 = "sha256-8XyOslMmzxmX2QsVzYzIJKNw6rVWJ7uDhU1jaKJ0Q8k=";
      #   # };
      # };
      config = {
        # overwriteProtocol = "https";
        dbtype = "mysql";
        adminuser = "TristonYoder";
        adminpassFile = "/etc/nextcloud-admin-pass";
      };
      settings = {
        default_phone_region = "US";
      };
      # Suggested by Nextcloud's health check.
      phpOptions."opcache.interned_strings_buffer" = "16";
    };
    # Nightly database backups.
    postgresqlBackup = {
      enable = true;
      startAt = "*-*-* 01:15:00";

    };
  };

}

