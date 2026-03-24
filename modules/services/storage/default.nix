{ ... }:
{
  # Import storage service modules
  imports = [
    ./nfs.nix
    ./nextcloud.nix
    ./samba.nix
    ./syncthing.nix
    ./wii-hdd-sync.nix
    ./zfs.nix
  ];
}

