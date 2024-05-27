{ self, config, lib, pkgs, ... }:
{
  # ZFS
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.requestEncryptionCredentials = true;
  networking.hostId = "aad77407";
  services.zfs.autoSnapshot.enable = true;
  services.zfs.autoScrub.enable = true;

  # ZPool Config
  # boot.inird.secrets."/zfs.key" = /root/zfs.key;
  # boot.zfs.extraPools = [ "data" ];
  # fileSystems."/boot".neededForBoot = true;

  # ZFS Load Data 
  systemd.services."zfs_load_data" = {
    path = [ pkgs.zfs ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      zpool import data -f || true 
    '';
    # Equivalant Actions ToDo:
    # sudo zpool import data -f
    # sudo zfs load-key data -L file:///root/zfs.key
    # sudo zfs mount data/media #etc
    wantedBy = [ "docker-compose-media-aq-root.target" "docker.target" ];
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

  # Mounts

  # fileSystems."/data/7andCo" =
  #   { device = "data/7andCo";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/backups" =
  #   { device = "data/backups";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/carolineyoder" =
  #   { device = "data/carolineyoder";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/docker-appdata" =
  #   { device = "data/docker-appdata";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/dropzone" =
  #   { device = "data/dropzone";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/media" =
  #   { device = "data/media";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/nextcloud" =
  #   { device = "data/nextcloud";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/proxmox" =
  #   { device = "data/proxmox";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/s3" =
  #   { device = "data/s3";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/tristonyoder" =
  #   { device = "data/tristonyoder";
  #     fsType = "zfs";
  #   };

  # fileSystems."/data/vm" =
  #   { device = "data/vm";
  #     fsType = "zfs";
  #   };

#   fileSystems."/data" =
#     { device = "data";
#       fsType = "zfs";
#     };

#   fileSystems."/data/web" =
#     { device = "data/web";
#       fsType = "zfs";
#     };

#   fileSystems."/data/web/com-carolineyoder" =
#     { device = "data/web/com-carolineyoder";
#       fsType = "zfs";
#     };

}
