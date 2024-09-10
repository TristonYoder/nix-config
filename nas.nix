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
      configure = "/data/docker-appdata/syncthing";   # Folder for Syncthing's settings and keys
  };

  # Configure the NFS server
  services.nfs.server = {
    enable = true;
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    extraNfsdConfig = '''';
    exports = ''
        /data/docker-appdata    10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/media             10.150.0.0/16(rw,fsid=1,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/tristonyoder      10.150.0.0/16(rw,fsid=2,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=0,no_subtree_check,crossmnt)
    '';
  };

  # Configure SMB
  services.samba-wsdd = {
    enable = true;  # make shares visible for windows 10 clients
    openFirewall = true;
  };
  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;
    extraConfig = ''
        workgroup = 7ANDCO
        server string = david
        netbios name = david
        security = user 
        #use sendfile = yes
        #max protocol = smb2
        # note: localhost is the ipv6 localhost ::1
        hosts allow = 10.150.0.0/16 100.64.0.0/10 127.0.0.1 localhost
        hosts deny = 0.0.0.0/0
        guest account = nobody
        map to guest = bad user
    '';
    shares = {
        # public = {
        # path = "/mnt/Shares/Public";
        # browseable = "yes";
        # "read only" = "no";
        # "guest ok" = "yes";
        # "create mask" = "0644";
        # "directory mask" = "0755";
        # "force user" = "username";
        # "force group" = "groupname";
        # };

        data = {
        path = "/data";
        browseable = "yes";
        # "valid users" = "tristonyoder";
        "read only" = "no";
        "guest ok" = "yes";
        "fruit:aapl" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "tristonyoder";
        # "force group" = "group";
        };
        media = {
        path = "/data/media";
        browseable = "yes";
        # "valid users" = "tristonyoder";
        "read only" = "no";
        "guest ok" = "yes";
        "fruit:aapl" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "tristonyoder";
        "force group" = "users";
        };
    };
  };
}
