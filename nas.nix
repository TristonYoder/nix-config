{ self, config, lib, pkgs, ... }:{
    # ZPool Config
    # boot.inird.secrets."/zfs.key" = /root/zfs.key;
#  boot.zfs.extraPools = [ "data" ];
    # fileSystems."/boot".neededForBoot = true;

    # Timeout Password on Reboot
    # boot.zfs.passwordTimeout = 10;

# Equivalant Actions ToDo:
# sudo zpool import data -f
# sudo zfs load-key data -L file:///root/zfs.key
# sudo zfs mount data/media #etc



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
  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;
    extraConfig = ''
        workgroup = WORKGROUP
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
        # "force group" = "group";
        };
    };
  };

services.samba-wsdd = {
  enable = true;
  openFirewall = true;
};

    # Mounts

#   fileSystems."/data/ix-applications/releases/com-carolineyoder" =
#     { device = "data/ix-applications/releases/com-carolineyoder";
#       fsType = "zfs";
#     };

#   fileSystems."/data/7andCo" =
#     { device = "data/7andCo";
#       fsType = "zfs";
#     };

#   fileSystems."/data/backups" =
#     { device = "data/backups";
#       fsType = "zfs";
#     };

#   fileSystems."/data/carolineyoder" =
#     { device = "data/carolineyoder";
#       fsType = "zfs";
#     };

#   fileSystems."/data/docker-appdata" =
#     { device = "data/docker-appdata";
#       fsType = "zfs";
#     };

#   fileSystems."/data/dropzone" =
#     { device = "data/dropzone";
#       fsType = "zfs";
#     };

#   fileSystems."/data/media" =
#     { device = "data/media";
#       fsType = "zfs";
#     };

#   fileSystems."/data/nextcloud" =
#     { device = "data/nextcloud";
#       fsType = "zfs";
#     };

#   fileSystems."/data/proxmox" =
#     { device = "data/proxmox";
#       fsType = "zfs";
#     };

#   fileSystems."/data/s3" =
#     { device = "data/s3";
#       fsType = "zfs";
#     };

#   fileSystems."/data/tristonyoder" =
#     { device = "data/tristonyoder";
#       fsType = "zfs";
#     };

#   fileSystems."/data/vm" =
#     { device = "data/vm";
#       fsType = "zfs";
#     };

#   fileSystems."/data" =
#     { device = "data";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications" =
#     { device = "data/ix-applications";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases" =
#     { device = "data/ix-applications/releases";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/catalogs" =
#     { device = "data/ix-applications/catalogs";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/jellyfin" =
#     { device = "data/ix-applications/releases/jellyfin";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/portainer" =
#     { device = "data/ix-applications/releases/portainer";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/syncthing" =
#     { device = "data/ix-applications/releases/syncthing";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale-librespeed" =
#     { device = "data/ix-applications/releases/tailscale-librespeed";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openspeedtest" =
#     { device = "data/ix-applications/releases/openspeedtest";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/jellyfin/charts" =
#     { device = "data/ix-applications/releases/jellyfin/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/portainer/charts" =
#     { device = "data/ix-applications/releases/portainer/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/jellyfin/volumes" =
#     { device = "data/ix-applications/releases/jellyfin/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/syncthing/charts" =
#     { device = "data/ix-applications/releases/syncthing/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/syncthing/volumes" =
#     { device = "data/ix-applications/releases/syncthing/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/portainer/volumes" =
#     { device = "data/ix-applications/releases/portainer/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale-librespeed/charts" =
#     { device = "data/ix-applications/releases/tailscale-librespeed/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale-librespeed/volumes" =
#     { device = "data/ix-applications/releases/tailscale-librespeed/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openspeedtest/charts" =
#     { device = "data/ix-applications/releases/openspeedtest/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openspeedtest/volumes" =
#     { device = "data/ix-applications/releases/openspeedtest/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/jellyfin/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/jellyfin/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/syncthing/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/syncthing/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/portainer/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/portainer/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale-librespeed/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/tailscale-librespeed/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openspeedtest/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/openspeedtest/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/k3s" =
#     { device = "data/ix-applications/k3s";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/syncthing/volumes/ix_volumes/config" =
#     { device = "data/ix-applications/releases/syncthing/volumes/ix_volumes/config";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/default_volumes" =
#     { device = "data/ix-applications/default_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/minio" =
#     { device = "data/ix-applications/releases/minio";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale" =
#     { device = "data/ix-applications/releases/tailscale";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/com-tristonyoder" =
#     { device = "data/ix-applications/releases/com-tristonyoder";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/photoprism" =
#     { device = "data/ix-applications/releases/photoprism";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/netbootxyz" =
#     { device = "data/ix-applications/releases/netbootxyz";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/com-tristonyoder/charts" =
#     { device = "data/ix-applications/releases/com-tristonyoder/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/truecommand" =
#     { device = "data/ix-applications/releases/truecommand";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/minio/charts" =
#     { device = "data/ix-applications/releases/minio/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openaudible" =
#     { device = "data/ix-applications/releases/openaudible";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/audiobookshelf" =
#     { device = "data/ix-applications/releases/audiobookshelf";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/photoprism/charts" =
#     { device = "data/ix-applications/releases/photoprism/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/com-tristonyoder/volumes" =
#     { device = "data/ix-applications/releases/com-tristonyoder/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/frigate" =
#     { device = "data/ix-applications/releases/frigate";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr" =
#     { device = "data/ix-applications/releases/homarr";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/netbootxyz/volumes" =
#     { device = "data/ix-applications/releases/netbootxyz/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/photoprism/volumes" =
#     { device = "data/ix-applications/releases/photoprism/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/minio/volumes" =
#     { device = "data/ix-applications/releases/minio/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/netbootxyz/charts" =
#     { device = "data/ix-applications/releases/netbootxyz/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/truecommand/volumes" =
#     { device = "data/ix-applications/releases/truecommand/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale/volumes" =
#     { device = "data/ix-applications/releases/tailscale/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/minio/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/minio/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/com-tristonyoder/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/com-tristonyoder/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/truecommand/charts" =
#     { device = "data/ix-applications/releases/truecommand/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/tailscale/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/netbootxyz/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/netbootxyz/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/audiobookshelf/volumes" =
#     { device = "data/ix-applications/releases/audiobookshelf/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/minio/volumes/ix_volumes/ix-postgres_data" =
#     { device = "data/ix-applications/releases/minio/volumes/ix_volumes/ix-postgres_data";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openaudible/volumes" =
#     { device = "data/ix-applications/releases/openaudible/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openaudible/charts" =
#     { device = "data/ix-applications/releases/openaudible/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/minio/volumes/ix_volumes/ix-postgres_backups" =
#     { device = "data/ix-applications/releases/minio/volumes/ix_volumes/ix-postgres_backups";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/photoprism/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/photoprism/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/truecommand/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/truecommand/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/audiobookshelf/charts" =
#     { device = "data/ix-applications/releases/audiobookshelf/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/frigate/charts" =
#     { device = "data/ix-applications/releases/frigate/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/photoprism/volumes/ix_volumes/ix-photoprism_import" =
#     { device = "data/ix-applications/releases/photoprism/volumes/ix_volumes/ix-photoprism_import";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/tailscale/charts" =
#     { device = "data/ix-applications/releases/tailscale/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/photoprism/volumes/ix_volumes/ix-photoprism_storage" =
#     { device = "data/ix-applications/releases/photoprism/volumes/ix_volumes/ix-photoprism_storage";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/openaudible/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/openaudible/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr/charts" =
#     { device = "data/ix-applications/releases/homarr/charts";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/netbootxyz/volumes/ix_volumes/config" =
#     { device = "data/ix-applications/releases/netbootxyz/volumes/ix_volumes/config";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr/volumes" =
#     { device = "data/ix-applications/releases/homarr/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/frigate/volumes" =
#     { device = "data/ix-applications/releases/frigate/volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/audiobookshelf/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/audiobookshelf/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/netbootxyz/volumes/ix_volumes/assets" =
#     { device = "data/ix-applications/releases/netbootxyz/volumes/ix_volumes/assets";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/homarr/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr/volumes/ix_volumes/icons" =
#     { device = "data/ix-applications/releases/homarr/volumes/ix_volumes/icons";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/frigate/volumes/ix_volumes" =
#     { device = "data/ix-applications/releases/frigate/volumes/ix_volumes";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/frigate/volumes/ix_volumes/config" =
#     { device = "data/ix-applications/releases/frigate/volumes/ix_volumes/config";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr/volumes/ix_volumes/configs" =
#     { device = "data/ix-applications/releases/homarr/volumes/ix_volumes/configs";
#       fsType = "zfs";
#     };

#   fileSystems."/data/ix-applications/releases/homarr/volumes/ix_volumes/data" =
#     { device = "data/ix-applications/releases/homarr/volumes/ix_volumes/data";
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
