{ ... }:
{
  # Import storage service modules
  imports = [
    ./nfs.nix
    ./samba.nix
    ./syncthing.nix
    ./zfs.nix
  ];
}

