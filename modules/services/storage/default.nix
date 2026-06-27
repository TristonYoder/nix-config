{ ... }:
{
  # Import storage service modules
  imports = [
    ./nfs.nix
    ./nextcloud.nix
    ./samba.nix
    ./syncthing.nix
    ./mp3-player-sync.nix
    ./wii-hdd-sync.nix
    ./zfs.nix
  ];
}

