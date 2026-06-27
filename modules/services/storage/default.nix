{ ... }:
{
  # Import storage service modules
  imports = [
    ./collabora.nix
    ./nfs.nix
    ./nextcloud.nix
    ./samba.nix
    ./syncthing.nix
    ./mp3-player-sync.nix
    ./wii-hdd-sync.nix
    ./zfs.nix
  ];
}

