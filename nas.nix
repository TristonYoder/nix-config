{ self, config, lib, pkgs, ... }:
{
  # ZFS
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.requestEncryptionCredentials = true;
  networking.hostId = "aad77407";
  services.zfs.autoSnapshot.enable = true;
  services.zfs.autoScrub.enable = true;

  # ZFS Load Data (Loads unencrypted datasets on encrypted root (past choices))
  systemd.services."zfs_load_data" = {
    path = [ pkgs.zfs ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      zpool import data -f || true 
    '';
    wantedBy = [ "docker-compose-media-aq-root.target" "docker.target" ];
  };

  # Configure SyncThing
  services.syncthing = {
      enable = true;
      user = "tristonyoder";
      dataDir = "/data/";    # Default folder for new synced folders
      configDir = "/data/docker-appdata/syncthing";   # Folder for Syncthing's settings and keys
      guiAddress = "0.0.0.0:8384";
  };
  networking.firewall.allowedTCPPorts = [ 8384 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];

  # Configure the NFS server
  services.nfs.server = {
    enable = true;
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    extraNfsdConfig = '''';
    exports = ''
        /data/docker-appdata    10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/media             10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/tristonyoder      10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/backups           10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
    '';
  };

  # Configure SMB
  services.samba-wsdd = {
    enable = true;  # make shares visible for windows 10 clients
    openFirewall = true;
  };
  services.samba = {
  enable = true;
  settings = {
    "data" = {
      path = "/data";
      writable = true;
      browseable = true;
      guestOk = false;
      validUsers = "tristonyoder";
    };
    "media" = {
      path = "/data/media";
      writable = false; # Read-only for everyone
      browseable = true;
      guestOk = true;   # Allow guest (read-only) access
    };
    "tristonyoder" = {
      path = "/data/tristonyoder";
      writable = true;
      browseable = true;
      guestOk = false;
      validUsers = "tristonyoder";
    };
    "carolineyoder" = {
      path = "/data/carolineyoder";
      writable = true;
      browseable = true;
      guestOk = false;
      validUsers = "carolineyoder tristonyoder";
    };
    "backups" = {
      path = "/data/backups";
      writable = true;
      browseable = true;
      guestOk = false;
      validUsers = "carolineyoder tristonyoder";
    };
  };
};

}
