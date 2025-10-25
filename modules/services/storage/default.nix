{ ... }:
{
  # Import storage service modules
  imports = [
    ./nfs.nix
    ./nextcloud.nix
    ./samba.nix
    ./syncthing.nix
    ./zfs.nix
  ];
}

